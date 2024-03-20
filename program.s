PORTB2 = $6000  ; Port B Data Bus             (VIA IC 2)
PORTA2 = $6001  ; Port A Data Bus             (VIA IC 2)
DDRB2  = $6002  ; Data Direction Register B   (VIA IC 2)
DDRA2  = $6003  ; Data Direction Register A   (VIA IC 2)
PCR2   = $600c  ; Peripheral Control Register (VIA IC 2)
IFR2   = $600d  ; Interupt Flag Register      (VIA IC 2)
IER2   = $600e  ; Interupt Enable Register    (VIA IC 2)

PORTB = $4000  ; Port B Data Bus             (VIA IC)
PORTA = $4001  ; Port A Data Bus             (VIA IC)
DDRB  = $4002  ; Data Direction Register B   (VIA IC)
DDRA  = $4003  ; Data Direction Register A   (VIA IC)
PCR   = $400c  ; Peripheral Control Register (VIA IC)
IFR   = $400d  ; Interupt Flag Register      (VIA IC)
IER   = $400e  ; Interupt Enable Register    (VIA IC)

DE    = %10000000  ; Display Enable
DRW   = %01000000  ; Display Read/Write
DRS   = %00100000  ; Display Register Select

; Keyboard Flags
RELEASE  = %00000001  ; Indicates if a key was just released
SHIFT    = %00000010  ; Indicates if the shift key is pressed
CAPSLOCK = %00000100  ; Indicates if the caps lock key is pressed


; RAM Data Addresses
kb_wptr   = $0000  ; Write pointer (1 byte)
kb_rptr   = $0001  ; Read pointer (1 byte)
kb_flags  = $0002  ; Keyboard flags (1 byte)
kb_buffer = $0200  ; 256 byte keyboard buffer $0200-02ff



; Specifies start of program ROM space
  .org $8000


; ROM Data
message: .asciiz "Hello World!"



; Program initilization
reset:
  ldx #$ff
  txs             ; Sets the stack to location $01ff

  lda #%00000001  ; Sets the interupt to trigger on positive active edge
  sta PCR2
  lda #%10000010  ; Sets the set bit. Enables CA1 VIA interupt pin
  sta IER2

  lda #%11111111  ; Set all pins on Port B to write
  sta DDRB
  lda #%11100000  ; Sets first three bits on Port A to write
  sta DDRA

  lda #%00111000  ; Set 8-bit mode. 2-line display. 5x8 font
  jsr lcd_instr
  lda #%00001110  ; Display on. Cursor on. Blink off.
  jsr lcd_instr
  lda #%00000110  ; Increment and shift cursor. Don't shift display
  jsr lcd_instr
  lda #%00000001  ; Clears the display
  jsr lcd_instr

  lda #$00        ; Sets A register to 0
  sta kb_wptr     ; Inits keyboard write pointer to 0
  sta kb_rptr     ; Inits keyboard read pointer to 0
  sta kb_flags    ; Inits all keyboard flags to 0

  cli             ; Clears the interupt


;  ldx #0             ; Sets the x register to 0
;print_message:
;  lda message,x      ; Loads a byte at message + x bytes
;  beq loop           ; Branches to loop when the end #00 byte is reached
;  jsr print_char     ; Prints the char
;  inx                ; Increments x register
;  jmp print_message

; Main program loop
loop:              
  sei               ; Sets interupt enable to disable interupts
  lda kb_rptr       ; Loads the read pointer into A
  cmp kb_wptr       ; Checks read ptr against write ptr
  cli               ; Clears the interupt enable
  bne key_pressed   ; If read ptr != write ptr then jump
  jmp loop

key_pressed:
  ldx kb_rptr       ; Loads read ptr into x
  lda kb_buffer, x  ; Grabs char at x pos in buffer
  jsr print_char    ; Prints the char
  inc kb_rptr       ; Increments read ptr
  jmp loop


; -------------------
; End of main routine
; -------------------



; SUBROUTINE
lcd_wait:
  pha
  lda #%00000000   ; Set all pins on Port B to read
  sta DDRB
lcd_busy:
  lda #DRW         ; Sets RW mode to read
  sta PORTA
  lda #(DRW | DE)  ; Set E bit to send instruction
  sta PORTA
  lda PORTB        ; Loads display state into A register
  and #%10000000   ; Sets all unnecicary pins to 0
  bne lcd_busy     ; Branches if z=0 indicating display is busy

  lda #DRW         ; Sets RW mode to read
  sta PORTA
  lda #%11111111   ; Set all pins on Port B to write
  sta DDRB
  pla
  rts
  


; SUBROUTINE
lcd_instr:
  jsr lcd_wait
  pha
  sta PORTB
  lda #0        ; Clear RS/RW/E bits
  sta PORTA
  lda #DE       ; Set E bit to send instruction
  sta PORTA
  lda #0        ; Clear RS/RW/E bits
  sta PORTA
  pla
  rts



; SUBROUTINE
print_char:
  jsr lcd_wait
  pha
  sta PORTB
  lda #DRS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(DRS | DE)  ; Set E bit to send instruction
  sta PORTA
  lda #DRS         ; Clear E bit
  sta PORTA
  pla
  rts



nmi:
  rti


; INTERUPT SUBROUTINE
; Reads keyboard inputs and writes to the kb_buffer
irq:
  pha               ; Push A to stack
  txa               ; Transfer RegX to RegA
  pha               ; Push transfered X to stack
  lda kb_flags      ; Loads current kb_flags into A
  and #RELEASE      ; Checks to see if release flag is set to 1
  beq read_key      ; Jmp to read_key if release is not set

  lda kb_flags      ; Loads current kb_flags back into A
  eor #RELEASE      ; Sets the release flag back to 0
  sta kb_flags      ; Stores new release flag into kb_flags
  lda PORTA2        ; Reads PORTA2 (clears interupt as well)
  cmp #$12          ; Checks if release scan code is Left Shift
  beq shift_up
  cmp #$59          ; Checks if release scan code is Right Shift
  beq shift_up
  jmp exit_irq      ; Don't read key since this was a release

shift_up:
  lda kb_flags      ; Load kb_flags RAM data into A
  eor #SHIFT        ; Sets the shift flag back to 0
  sta kb_flags      ; Stores A into kb_flags RAM
  jmp exit_irq
  
read_key:
  lda PORTA2        ; Loads keyboard byte code into A register
  cmp #$f0          ; Checks if scan code is release code
  beq key_release   
  cmp #$12          ; Checks if scan code is Left Shift
  beq shift_down    
  cmp #$59          ; Checks if scan code is Right Shift
  beq shift_down
  cmp #$58          ; Checks if scan code is Caps Lock
  beq capslock_down
  cmp #$76          ; Checks if scan code is Escape
  beq clear_screen
  cmp #$66          ; Checks if scan code is Backspace
  beq write_backspace

  tax               ; Loads kb scan code into X register
  lda kb_flags      ; Loads kb_flags RAM data into A
  and #SHIFT        ; Check if shift flag is 1
  bne shifted_key   ; Writes shifted key to buffer instead
  lda kb_flags      ; Reloads kb_flags RAM data into A
  and #CAPSLOCK     ; Check if capslock flag is 1
  bne shifted_key
  
  lda keymap, x     ; Loads letter that kb scan code maps to
  jmp write_key

shifted_key:
  lda keymap_shifted, x  ; Loads shifted letter that code maps to

write_key:
  ldx kb_wptr       ; Loads write pointer into X
  sta kb_buffer, x  ; Stores A into addr kb_buffer + x
  inc kb_wptr       ; Increment write pointer
  jmp exit_irq      ; Skips key release if not release code

shift_down:
  lda kb_flags      ; Load kb_flags RAM data into A
  ora #SHIFT        ; ORs shift bit flag setting it to 1
  sta kb_flags      ; Stores A into kb_flags RAM
  jmp exit_irq

capslock_down:
  lda kb_flags      ; Load kb_flags RAM data into A
  eor #CAPSLOCK     ; ORs capslock bit flag reversing it
  sta kb_flags      ; Stores A into kb_flags RAM
  jmp exit_irq

clear_screen:
  lda #%00000001    ; Loads clear display instruction into A
  jsr lcd_instr     ; Calls subroutine to execute clear command
  jmp exit_irq

write_backspace:
  lda #%00010000    ; Shift cursor to the left lcd instruction
  jsr lcd_instr
  lda #" "          ; Loads blank character into A
  jsr print_char    ; Prints the blank char
  lda #%00010000    ; Shift cursor to the left lcd instruction
  jsr lcd_instr
  jmp exit_irq

key_release:
  lda kb_flags      ; Load kb_flags RAM data into A
  ora #RELEASE      ; ORs release bit flag setting it to 1
  sta kb_flags      ; Stores A into kb_flags RAM

exit_irq:
  pla               ; Pop transfered X back into A
  tax               ; Transfer X val from RegA back to RegX
  pla               ; Pop A val into RegA
  rti               ; Return from interupt



; 512 bytes for keyboard letters
; Addr $fd00-$ff00
  .org $fd00  
keymap:
  .byte "????????????? `?" ; 00-0F
  .byte "?????q1???zsaw2?" ; 10-1F
  .byte "?cxde43?? vftr5?" ; 20-2F
  .byte "?nbhgy6???mju78?" ; 30-3F
  .byte "?,kio09??./l;p-?" ; 40-4F
  .byte "??'?[=?????]?\??" ; 50-5F
  .byte "?????????1?47???" ; 60-6F
  .byte "0.2568???+3-*9??" ; 70-7F
  .byte "????????????????" ; 80-8F
  .byte "????????????????" ; 90-9F
  .byte "????????????????" ; A0-AF
  .byte "????????????????" ; B0-BF
  .byte "????????????????" ; C0-CF
  .byte "????????????????" ; D0-DF
  .byte "????????????????" ; E0-EF
  .byte "????????????????" ; F0-FF
keymap_shifted:
  .byte "????????????? ~?" ; 00-0F
  .byte "?????Q!???ZSAW@?" ; 10-1F
  .byte "?CXDE#$?? VFTR%?" ; 20-2F
  .byte "?NBHGY^???MJU&*?" ; 30-3F
  .byte "?<KIO)(??>?L:P_?" ; 40-4F
  .byte '??"?{+?????}?|??' ; 50-5F
  .byte "?????????1?47???" ; 60-6F
  .byte "0.2568???+3-*9??" ; 70-7F
  .byte "????????????????" ; 80-8F
  .byte "????????????????" ; 90-9F
  .byte "????????????????" ; A0-AF
  .byte "????????????????" ; B0-BF
  .byte "????????????????" ; C0-CF
  .byte "????????????????" ; D0-DF
  .byte "????????????????" ; E0-EF
  .byte "????????????????" ; F0-FF




  .org $fffa  ; First addr 6502 CPU looks for program execution
  .word nmi
  .word reset
  .word irq
