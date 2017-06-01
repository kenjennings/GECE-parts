;===============================================================================
; Breakout Arcade -- 1976
; Conceptualized by Nolan Bushnell and Steve Bristow.
; Built by Steve Wozniak.
; https://en.wikipedia.org/wiki/Breakout_(video_game)
;===============================================================================
; C64 Breakout clone -- 2016
; Written by Darren Du Vall aka Sausage-Toes
; source at: 
; Github: https://github.com/Sausage-Toes/C64_Breakout
;===============================================================================
; C64 Breakout clone ported to Atari 8-bit -- 2017
; Atari-fied by Ken Jennings
; Build for Atari using eclipse/wudsn/atasm on linux
; Source at:
; Github: https://github.com/kenjennings/C64-Breakout-for-Atari
; Google Drive: https://drive.google.com/drive/folders/0B2m-YU97EHFESGVkTXp3WUdKUGM
;===============================================================================
; Breakout: Gratuitous Eye Candy Edition -- 2017
; Written by Ken Jennings
; Build for Atari using eclipse/wudsn/atasm on linux
; Source at:
; Github: https://github.com/kenjennings/Breakout-GECE-for-Atari
; Google Drive: https://drive.google.com/drive/folders/
;===============================================================================

;===============================================================================
; **   **   **    ******  **  **
; *** ***  ****     **    *** **
; ******* **  **    **    ******
; ** * ** **  **    **    ******
; **   ** ******    **    ** ***
; **   ** **  **  ******  **  ** 
;===============================================================================

;===============================================================================
;   ATARI SYSTEM INCLUDES
;===============================================================================
; Various Include files that provide equates defining 
; registers and the values used for the registers:
;
	.include "ANTIC.asm" 
	.include "GTIA.asm"
	.include "POKEY.asm"
	.include "PIA.asm"
	.include "OS.asm"
	.include "DOS.asm" ; This provides the LOMEM, start, and run addresses.

	.include "macros.asm"


;===============================================================================
;   VARIOUS CONSTANTS AND LIMITS
;===============================================================================
; Let's define some useful offsets and sizes. 
; Could become useful somewhere else.
;
BRICK_LEFT_OFFSET =   3  ; offset from normal PLAYFIELD LEFT edge to left edge of brick 
BRICK_RIGHT_OFFSET =  12 ; offset from normal PLAYFIELD LEFT edge to the right edge of first brick

BRICK_PIXEL_WIDTH =   10 ; Actual drawn pixels in brick.
BRICK_WIDTH =         11 ; including the trailing blank space separating bricks 

BRICK_TOP_OFFSET =     78  ; First scan line of top line of bricks.
BRICK_TOP_END_OFFSET = 82  ; Last scan line of the top line of bricks.
BRICK_BOTTOM_OFFSET =  131 ; Last scan line of bottom line of bricks.

BRICK_LINE_HEIGHT =    5   ; Actual drawn graphics scanlines.
BRICK_HEIGHT =         7   ; including the following blank lines (used when multiplying for position) 
;
; Playfield MIN/MAX travel areas relative to the ball.
;
MIN_PIXEL_X = PLAYFIELD_LEFT_EDGE_NORMAL+BRICK_LEFT_OFFSET ; 48 + 3 = 51
MAX_PIXEL_X = MIN_PIXEL_X+152 ; Actual last color clock of last brick. 51 + 152 = 203

PIXELS_COLS = MAX_PIXEL_X-MIN_PIXEL_X+1 ; number of real pixels on line (153)

MIN_BALL_X =  MIN_PIXEL_X ; because PM/left edge is same
MAX_BALL_X =  MAX_PIXEL_X-1 ; because ball is 2 color clocks wide

MIN_PIXEL_Y = 53 ; Top edge of the playfield.  just a guess right now.
MAX_PIXEL_Y = 230 ; bottom edge after paddle.  lose ball here.

; Ball travel when bouncing from walls and bricks will simply negate 
; the current horizontal or vertical direction.
; Ball travel when bouncing off the paddle will require lookup tables
; to manage angle (and speed changes).
;
; Playfield MIN/MAX travel areas relative to the Paddle.
;
; Paddle travel is only horizontal. But the conversion from paddle 
; value (potentiometer) to paddle Player on screen will have different
; tables based on wide paddle and narrow paddle sizes.
; The paddle also is allowed to travel beyond the left and right sides
; of the playfield far enough that only an edge of the paddle is 
; visible for collision on the playfield.
; The size of the paddle varies the coordinates for this.
;
; Paddle limits:
; O = Offscreen/not playfield
; X = ignored playfield 
; P = Playfield 
; T = Paddle Pixels
;
; (Normal  Left)     (Normal Right)
; OOOxxxPP           PPxxxxOOO 
; TTTTTTTT           TTTTTTTT
; MIN = Playfield left edge normal - 3
; MAX = Playfield right edge - 5
;
; (Small  Left)     (Small Right)
; OOOxxxPP           PPxxxxOOO 
;    TTTTT           TTTTT
; MIN = Playfield left edge normal
; MAX = Playfield right edge - 5
;
PADDLE_NORMAL_MIN_X = PLAYFIELD_LEFT_EDGE_NORMAL-3
PADDLE_NORMAL_MAX_X = PLAYFIELD_RIGHT_EDGE_NORMAL-5

PADDLE_SMALL_MIN_X = PLAYFIELD_LEFT_EDGE_NORMAL
PADDLE_SMALL_MAX_X = PLAYFIELD_RIGHT_EDGE_NORMAL-5

; FYI:
; PLAYFIELD_LEFT_EDGE_NORMAL  = $30 ; First/left-most color clock horizontal position
; PLAYFIELD_RIGHT_EDGE_NORMAL = $CF ; Last/right-most color clock horizontal position

;  Offset to make binary 0 to 9 into text  
; 48 for PETSCII/ATASCII,  16 for Atari internal
NUM_BIN_TO_TEXT = 16  

; Adjusted playfield width for exaluating paddle position.
; This is needed several times, so is computed once here:
; Screen max X limit is 
; PLAYFIELD_RIGHT_EDGE_NORMAL/$CF -  PLAYFIELD_LEFT_EDGE_NORMAL/$30 == $9F
; Then, this needs to subtract 11 (12-1) for the size of the paddle, == $93.
PADDLE_MAX = (PLAYFIELD_RIGHT_EDGE_NORMAL-PLAYFIELD_LEFT_EDGE_NORMAL-11)


;===============================================================================
;    ZERO PAGE VARIABLES
;===============================================================================
; These will be used when needed to pass extra parameters to 
; routines when you can't use A, X, Y registers for other reasons.
; Essentially, think of these as extra data registers.
;
; Also used as permanent variables with lower latency than regular memory.

; The Atari OS has defined purpose for the first half of Page Zero 
; locations.  Since no Floating Point will be used here we'll 
; borrow the FP registers in Page Zero.

PARAM_00 = $D4 ; ZMR_ROBOTO  -- Is Mr Roboto playing the automatic demo mode? init 1/yes
PARAM_01 = $D6 ; ZDIR_X      -- +1 Right, -1 Left.  Indicates direction of travel.
PARAM_02 = $D7 ; ZDIR_Y      -- +1 Down, -1 Up.  Indicates direction of travel.
PARAM_03 = $D8 ; ZCOLLISION  -- Is Brick present at tested location? 0 = no, 1 = yes
PARAM_04 = $D9 ; ZBRICK_LINE -- coord_Y reduced to line 1-8
PARAM_05 = $DA ; ZBRICK_COL  -- coord_X reduced to brick number 1-14
PARAM_06 = $DB ; ZCOORD_Y    -- coord_Y for collision check
PARAM_07 = $DC ; ZCOORD_X    -- coord_X for collision check  
PARAM_08 = $DD ;   
;
; And more Zero Page fun.  This is assembly, dude.  No BASIC in sight anywhere.
; No BASIC means we can get craaaazy with the second half of Page Zero.
;
; In fact, there's no need to have the regular game variables out in high memory.  
; For starters, all the Byte-sized values are hereby moved to Page 0.
;
PARAM_09 = $80 ; TITLE_STOP_GO - set by mainline to indicate title is working or not.

PARAM_10 = $81 ; TITLE_PLAYING - flag indicates title animation stage in progress. 
PARAM_11 = $82 ; TITLE_TIMER - set by Title handler for pauses.
PARAM_12 = $83 ; TITLE_HPOSP0 - Current P/M position of fly-in letter. or 0 if no letter.
PARAM_13 = $84 ; TITLE_SIZEP0 - current size of Player 0
PARAM_14 = $85 ; TITLE_GPRIOR - Current P/M Priority in title. 
PARAM_15 = $86 ; TITLE_VSCROLL - current fine scroll position. (0 to 7)
PARAM_16 = $87 ; TITLE_CSCROLL - current coarse scroll position. (0 to 4)
PARAM_17 = $88 ; TITLE_CURRENT_FLYIN - current index (0 to 7) into tables for visible stuff in table below.
PARAM_18 = $89 ; TITLE_SCROLL_COUNTER - index into the tables above. 0 to 32
PARAM_19 = $8a ; TITLE_WSYNC_OFFSET - Number of scan lines to drop through before color draw

PARAM_20 = $8b ; TITLE_WSYNC_COLOR - Number of scan lines to do color bars
PARAM_21 = $8c ; TITLE_COLOR_COUNTER - Index into color table
PARAM_22 = $8d ; TITLE_DLI_PMCOLOR - PM Index into TITLE_DLI_PMCOLOR_TABLE
PARAM_23 = $8e ; THUMPER_PROXIMITY/THUMPER_PROXIMITY_TOP
PARAM_24 = $8f ; THUMPER_PROXIMITY_LEFT
PARAM_25 = $90 ; THUMPER_PROXIMITY_RIGHT
PARAM_26 = $91 ; THUMPER_FRAME/THUMPER_FRAME_TOP
PARAM_27 = $92 ; THUMPER_FRAME_LEFT
PARAM_28 = $93 ; THUMPER_FRAME_RIGHT
PARAM_29 = $94 ; THUMPER_FRAME_LIMIT/THUMPER_FRAME_LIMIT_TOP

PARAM_30 = $95 ; THUMPER_FRAME_LIMIT_LEFT
PARAM_31 = $96 ; THUMPER_FRAME_LIMIT_RIGHT
PARAM_32 = $97 ; THUMPER_COLOR/THUMPER_COLOR_TOP
PARAM_33 = $98 ; THUMPER_COLOR_LEFT
PARAM_34 = $99 ; THUMPER_COLOR_RIGHT
PARAM_35 = $9a ; BRICK_SCREEN_START_SCROLL
PARAM_36 = $9b ; BRICK_SCREEN_IMMEDIATE_POSITION
PARAM_37 = $9c ; BRICK_SCREEN_IN_MOTION
PARAM_38 = $9d ; ENABLE_BOOM
PARAM_39 = $9e ; ENABLE_BALL

PARAM_40 = $9f ; BALL_CURRENT_X
PARAM_41 = $a0 ; BALL_CURRENT_Y
PARAM_42 = $a1 ; BALL_HPOS
PARAM_43 = $a2 ; BALL_NEW_X
PARAM_44 = $a3 ; BALL_NEW_Y
PARAM_45 = $a4 ; BALL_COLOR
PARAM_46 = $a5 ; BALL_SPEED_CURRENT_SEQUENCE
PARAM_47 = $a6 ; BALL_SPEED_CURRENT_STEP
PARAM_48 = $a7 ; BALL_BOUNCE_COUNT
PARAM_49 = $a8 ; ENABLE_CREDIT_SCROLL - MAIN: Flag to stop/start scrolling/visible text

PARAM_50 = $a9 ; SCROLL_DO_FADE - MAIN: 0 = no fade.  1= fade up.  2 = fade down.
PARAM_51 = $aa ; SCROLL_TICK_DELAY - MAIN: number of frames to delay per scroll step.
PARAM_52 = $ab ; SCROLL_BASE - MAIN: Base table to start scrolling
PARAM_53 = $ac ; SCROLL_MAX_LINES - MAIN: number of lines in scroll before restart.
PARAM_54 = $ad ; SCROLL_CURRENT_TICK - VBI: Current tick for delay, decrementing to 0.
PARAM_55 = $ae ; SCROLL_IN_FADE - VBI: fade is in progress? 0 = no. 1 = up. 2 = down
PARAM_56 = $af ; SCROLL_CURRENT_FADE - VBI/DLI: VBI set for DLI - Current Fade Start position
PARAM_57 = $b0 ; SCROLL_CURRENT_LINE - VBI: increment for start line of window.
PARAM_58 = $b1 ; SCROLL_CURRENT_VSCROLL -  VBI/DLI: VBI sets for DLI -- Current Fine Vertical Scroll vertical position. 
PARAM_59 = $b2 ; ENABLE_PADDLE

PARAM_60 = $b3 ;   PADDLE_SIZE
PARAM_61 = $b4 ;   PADDLE_HPOS
PARAM_62 = $b5 ;   PADDLE_STRIKE
PARAM_63 = $b6 ;   PADDLE_FRAME
PARAM_64 = $b7 ;   PADDLE_STRIKE_COLOR
PARAM_65 = $b8 ; ENABLE_BALL_COUNTER
PARAM_66 = $b9 ;   BALL_COUNTER
PARAM_67 = $ba ;   BALL_TITLE_HPOS - DLI: Add 8 for PM1 and then same for PM2
PARAM_68 = $bb ;   SINE_WAVE_DELAY
PARAM_69 = $bc ;   BALL_COUNTER_COLOR

PARAM_70 = $bd ; ENABLE_SCORE
PARAM_71 = $be ;   REAL_SCORE_DIGITS
PARAM_72 = $bf ;   DISPLAYED_SCORE_DELAY
PARAM_73 = $c0 ;   DISPLAYED_BALLS_SCORE_COLOR_INDEX
PARAM_74 = $c1 ; ENABLE_SOUND
PARAM_75 = $c2 ;   SOUND_CURRENT_VOICE
PARAM_76 = $c3 ; ZAUTO_NEXT
PARAM_77 = $c4 ; ZBRICK_COUNT  - init 112 (full screen of bricks)
PARAM_78 = $c5 ; ZBRICK_POINTS - init 0 - point value of brick to add to score.
PARAM_79 = $c6 ; ZBALL_COUNT   - init 5

PARAM_80 = $c7 ; 
PARAM_81 = $c8 ;    
PARAM_82 = $c9 ;    
PARAM_83 = $ca ;    
PARAM_84 = $cb ; 
PARAM_85 = $cc ;    
PARAM_86 = $cd ; 
PARAM_87 = $ce ; 
PARAM_88 = $cf ; 
PARAM_89 = $d0 ; DIAG_TEMP1

ZEROPAGE_POINTER_1 = $DE ; 
ZEROPAGE_POINTER_2 = $E0 ; 
ZEROPAGE_POINTER_3 = $E2 ; 
ZEROPAGE_POINTER_4 = $E4 ; 
ZEROPAGE_POINTER_5 = $E6 ; 
ZEROPAGE_POINTER_6 = $E8 ; 
ZEROPAGE_POINTER_7 = $EA ; 
ZEROPAGE_POINTER_8 = $EC ; ZBRICK_BASE   -- Pointer to start of bricks on a line.
ZEROPAGE_POINTER_9 = $EE ; ZTITLE_COLPM0 -- VBI sets for DLI to use

;===============================================================================
;   LOAD START
;===============================================================================

;	*=LOMEM_DOS     ; $2000  ; After Atari DOS 2.0s
;	*=LOMEM_DOS_DUP ; $3308  ; Alternatively, after Atari DOS 2.0s and DUP

; This will not be a terribly big or complicated game.  Begin after DUP.

	*=$3400 

;===============================================================================


;===============================================================================
;   VARIABLES AND DATA
;===============================================================================

ZMR_ROBOTO =  PARAM_00 ; Is Mr Roboto playing the automatic demo mode? init 1/yes

ZDIR_X =      PARAM_01 ; +1 Right, -1 Left.  Indicates direction of travel.
 
ZDIR_Y =      PARAM_02 ; +1 Down, -1 Up.  Indicates direction of travel.

ZCOLLISION =  PARAM_03 ; Is Brick present at tested location? 0 = no, 1 = yes

ZBRICK_LINE = PARAM_04 ; Ycoord reduced to line 1-8

ZBRICK_COL =  PARAM_05 ; Xcoord reduced to brick number 1-14

ZCOORD_Y =    PARAM_06 ; Ycoord for collision check

ZCOORD_XP =   PARAM_07 ; Xcoord for collision check  


; flag when timer counted (29 sec). Used on the
; title and game over  and auto play screens. When auto_wait
; ticks it triggers automatic transition to the 
; next screen.
ZAUTO_NEXT =    PARAM_76 ; .byte 0

ZBRICK_COUNT =  PARAM_77 ; .byte 112 (full screen of bricks, 8 * 14)

ZBRICK_POINTS = PARAM_78 ; .byte $00

ZBALL_COUNT =   PARAM_79 ; .byte $05


ZBRICK_BASE =   ZEROPAGE_POINTER_8 = $EC ; Pointer to start of bricks on a line.

ZTITLE_COLPM0 = ZEROPAGE_POINTER_9 = $EE ; VBI sets for DLI to use




;===============================================================================
;	GAME INTERRUPT INCLUDES
;===============================================================================

;	.include "vbi.asm"
;===============================================================================
; **  **  *****   ****** 
; **  **  **  **    **   
; **  **  *****     **   
; **  **  **  **    **   
;  ****   **  **    **   
;   **    *****   ******  
;===============================================================================

;
; Insert the game's routine in the Deferred Vertical Blank Interrupt.
;
Set_VBI
	ldy #<Breakout_VBI ; LSB for routine
	ldx #>Breakout_VBI ; MSB for routine

	lda #7             ; Set Interrupt Vector 7 for Deferred VBI

	jsr SETVBV         ; and away we go.

	rts

;	
; Remove the game's Deferred Vertical Blank Interrupt.
;
Remove_VBI
	ldy #<XITVBV ; LSB of JMP to end deferred VBI
	ldx #>XITVBV ; MSB of JMP to end deferred VBI

	lda #7       ; Set Interrupt Vector 7 for Deferred Vertical Blank Interrupt.

	jsr SETVBV  ; and away we go.

	rts


.local
;
; MAIN directs things to happen. The magic of that happening is 
; (decided) here.  That is, much of the game guts, animation, and 
; timing either occurs here or is established here.  For the most 
; part, DLIs are only transferring values to registers per the
; directions determined here. 
;
Breakout_VBI

	; Enforce sanity during the intial hacking and testing phase.
	; Force initial display values to be certain everything begins 
	; at a known state.
	; Force the initial DLI just in case one goes crazy and the 
	; DLI chaining gets messed up. 
	; This may be commented out when code is more final.

;	lda #<DISPLAY_LIST ; Display List
;	sta SDLSTL
;	lda #>DISPLAY_LIST
;	sta SDLSTH
	
;	lda #<DISPLAY_LIST_INTERRUPT ; DLI Vector
;	sta VDSLST
;	lda #>DISPLAY_LIST_INTERRUPT
;	sta VDSLST+1
	;
	; Turn on Display List DMA
	; Turn on Player/Missile DMA
	; Set Playfield Width Narrow (a temporary thing for the title section)
	; Set Player/Missile DMA to 1 Scan line resolution/updates
	;
;	lda #[ENABLE_DL_DMA|ENABLE_PM_DMA|PLAYFIELD_WIDTH_NARROW|PM_1LINE_RESOLUTION]
;	sta SDMCTL ; Display DMA control
	
;	lda #>PLAYER_MISSILE_BASE ; Player/Missile graphics memory.
;	sta PMBASE
	
	lda TITLE_HPOSP0    ; set horizontal position for Player as Title character
	sta HPOSP0
	
;	lda #PM_SIZE_NORMAL ; set size for Player as Title character 
;	sta SIZEP0
	;
	; Set Missiles = 5th Player (COLPF3)
	; Set Priority with Players/Missiles on top
	;
;	lda #[FIFTH_PLAYER|1]  
;	sta GPRIOR

;	lda #[ENABLE_PLAYERS|ENABLE_MISSILES]
;	sta GRACTL ; Graphics Control, P/M DMA 

;	lda #[NMI_DLI|NMI_VBI] ; Set DLI and VBI Interrupt flags ON
;	sta NMIEN
	
;	lda #4 ; Finescrolling. 
;	sta HSCROL      ; Title text line is shifted by HSCROLL to center it.
;	lda #0
;	sta VSCROL

	lda #>CHARACTER_SET_01 ; Character set for title
	sta CHBASE
	

	
; ==============================================================
; TITLE FLY IN
; ==============================================================
; It figures that the first idea to pop into the head in the 
; gratuitous eye candy department and the first to work on is 
; just about the most complicated thing going on in the program.
;
; The animated title has different phases (controlled by TITLE_PLAYING)
; 0 == not running -- title lines in 0/empty state.  (Game Over and main Title)
; 1 == clear. no movement. (Pause for a couple seconds before animation starts.)
; 2 == Text fly-in is in progress.
;      a) P/M hold bitmap of character and moves from right to left to its 
;         target location on screen
;      b) At target position the character values are put into Title0 and Title1 lines
;         and the P/M is removed from screen to HPOS value 0.
;      c) do until all 8 characters have traveled on to the screen.
; 3 == pause for a couple seconds for public admiration. 
; 4 == Text VSCROLLs to the top of the screen.  
;      a) when complete reset/return to state 1 for pause.
;
; (Estimating that even this could get boring after a while... thinking
; about doing random horizontal and vertical scrolling to move the title
; off the top of the screen.) 
	
	; If Title is NOT running, and the main 
	; line wants it started, then start...
	
	ldy TITLE_PLAYING  ; Is title currently running?
	bne Run_Title      ; >0, yes.  continue to run.
	                   ; no. it is off.
	lda TITLE_STOP_GO  ; Does main line want to start title?
	bne Start_Title    ; Yes, begin title.

	jmp End_Title      ; No.  Skip title things.

Stop_Title  ; stop/zero everything.
	        ; reset to empty title.
	lda #0
	sta TITLE_PLAYING
	sta TITLE_CURRENT_FLYIN

	sta TITLE_HPOSP0
	sta TITLE_SIZEP0

	ldx #0
	jsr Update_Title_Scroll ; Set vertical scroll and DLI values
	
	jsr Clear_Title_Lines   ; Make sure Title text is erased
	
	lda #<TITLE_FRAME_EMPTY
	sta DISPLAY_LIST_TITLE_VECTOR ; Empty scroll window
	
	jmp End_Title
	
Start_Title                 ; Step into the first phase -- pause before fly-in
	ldy #1                  ; Enagage initial pause
	sty TITLE_PLAYING

	; Prep values for Stage 1.
	lda #120
	sta TITLE_TIMER

Run_Title
	lda TITLE_STOP_GO       ; Does Mainline want this to stop?
	beq Stop_Title          ; 0. Yes. clean screen.

	ldx TITLE_COLOR_COUNTER ; Always move the colors.
	inx                     ; next index in color table
	cpx #43                 ; 42 is last color index for title colors.
	bne Update_Color_Counter
	ldx #0                  ; Reset

Update_Color_Counter
	stx TITLE_COLOR_COUNTER
  
Title_Pause_1               ; Pause before title ?
	ldy TITLE_PLAYING
	cpy #1                  ; Is this #1 == Clear, no movement?
	bne Title_FlyIn         ; No, things are in motion. go to next phase

	ldx TITLE_TIMER
	beq SetDoFlyingText     ; It is at 0, so initilize next phase.
	dex                     ; Decrement timer
	stx TITLE_TIMER
	
	jmp End_Title           ; Done messing with title until timer expires.

SetDoFlyingText
	lda #0                  ; No. Do Flying Text
	sta TITLE_CURRENT_FLYIN ; start at first character in list
	sta TITLE_HPOSP0        ; reset HPOS to off screen.

	tax                     ; to update TITLE_SCROLL_COUNTER 
	jsr Update_Title_Scroll  

	jsr Clear_Title_Lines

	ldy #2                  ; Engage fly-in
	sty TITLE_PLAYING

	jmp End_Title

; FLY IN:  Things going on....
; A P/M letter is in motion, OR
; (a P/M letter reached its target and must be replaced by a character)
; Time to start a new letter in motion, OR
; All letters are displayed, set mode to  Pause to admire the title.
Title_FlyIn 
	ldy TITLE_PLAYING
	cpy #2 ; Is this #2 == Text fly-in is in progress.
	bne Title_Pause_2

	ldx TITLE_HPOSP0 ; if this is non-zero then a letter is in motion
	bne FlyingChar
	
	ldx TITLE_CURRENT_FLYIN ; if this is 8 then we should  be in admiration mode
	cpx #8 ; The scroller will reset this to 0 when done.
	bne FlyInStartChar
	
	ldy #3 ; DONE. Set to do the next step -- pause for admiration.
	sty TITLE_PLAYING

	ldy #120 ; how long to pause...
	sty TITLE_TIMER
	bne Title_Pause_2

; FLY IN PART 1 - Start the character
; establish the next character to fly in.
FlyInStartChar
	lda #$FE ; extreme right side
	sta TITLE_HPOSP0 ; new horizontal position.
	ldx TITLE_CURRENT_FLYIN ; which character ?

	ldy TITLE_DLI_PMCOLOR_TABLE,x ; Tell DLI which color for Flying letter
	sty TITLE_DLI_PMCOLOR
	
	lda TITLE_DLI_COLPM_TABLE_LO,y
	sta ZTITLE_COLPM0       ; Page 0 address pointer for DLI_1
	lda TITLE_DLI_COLPM_TABLE_HI,y
	sta ZTITLE_COLPM0+1 

	; Copy character image to Player
	ldy TITLE_PM_IMAGE_LIST,x    ; get starting image offset for character
	ldx #25                      ; destination scan line 
CopyCharToPM
	lda [CHARACTER_SET_01+$A8],y ; copy from character set
	sta PMADR_BASE0,x            ; to the P/M image memory
	iny
	inx
	cpx #41                      ; ending scan line (16 total) 
	bne CopyCharToPM

	ldx TITLE_HPOSP0
    
; FLY IN PART 2 - Move the current P/M character
FlyingChar
	dex ; move P/M left 2 color clocks
    beq ?Update_Title_HPOS
	dex
?Update_Title_HPOS
	stx TITLE_HPOSP0 ; and set it.
	txa             ; needs to be in A so we can compare from a table.
	ldx TITLE_CURRENT_FLYIN 
	cmp TITLE_PM_TARGET_LIST,x ; destination PM position for character
	bne Title_Pause_2
	; the flying P/M has reached target position. 
	; Replace it with the character on screen.
	ldy TITLE_TEXT_CHAR_POS,x ; get corresponding character postition.
	lda TITLE_CHAR_LIST,x ; get character
	sta TITLE_LINE0,y ; top half of title
	clc
	adc #1 ; determine the next screen byte value
	sta TITLE_LINE1,y ; bottom half of title
	
	; Setup for next Character
	inc TITLE_CURRENT_FLYIN ; next flying chraracter
	lda #0
	sta TITLE_HPOSP0 ; set P/M offscreen

	
; PAUSE:  Admire the title
Title_Pause_2
	ldy TITLE_PLAYING
	cpy #3 ; Is this #3 == pause for public admiration.
	bne Title_Scroll

	dec TITLE_TIMER
	lda TITLE_TIMER
	
	bne Title_Scroll
	
	; Timer Reached 0.
	; Init for next phase -- scrolling...
	
	ldy #4 ; Text  VSCROLL to top of screen
	sty TITLE_PLAYING		
	; Note that the end of Pause 1 updated the scroll counter to 0 and
	; reset all related values to the initial position.
	
; SCROLLING TITLE - Vertical scroll up
Title_Scroll
	ldy TITLE_PLAYING
	cpy #4; Is this #4 == Text  VSCROLL to top of screen in progress.
	bne End_Title

	ldx TITLE_SCROLL_COUNTER
	inx
	cpx #32 ; 0 to 31 is valid
	bne Title_update
	
	; Reached the end of scroll.  Next Phase is back to pause.
	ldy #1
	sty TITLE_PLAYING
	jsr Clear_Title_Lines

	ldx #0 ; reset scroll and DLI to initial position.
Title_Update
	jsr Update_Title_Scroll
		
; End of Title section.
End_Title

;	lda #12
;		sta TITLE_WSYNC_COLOR

;===============================================================================
; THE END OF USER DEFERRED VBI ROUTINE 
;===============================================================================

Exit_VBI
; Finito.
	jmp XITVBV


.local
;=============================================
; Used more than once to initialize
; and then run the vertical scroll in the title.
; Given the value of X, set the 
; TITLE_SCROLL_COUNTER, and update 
; all the scrolling variables.
Update_Title_Scroll
	stx TITLE_SCROLL_COUNTER

	lda TITLE_VSCROLL_TABLE,x ; Fine scroll position
	sta TITLE_VSCROLL

	ldy TITLE_CSCROLL_TABLE,x ; Coarse scroll position
	lda TITLE_FRAME_TABLE,y
	sta DISPLAY_LIST_TITLE_VECTOR

	lda TITLE_WSYNC_OFFSET_TABLE,x ; Line Counter before color bars
	sta TITLE_WSYNC_OFFSET
	
	lda TITLE_WSYNC_COLOR_TABLE,x  ; Lines in the color bars
	sta TITLE_WSYNC_COLOR
	
	lda TITLE_COLOR_COUNTER_PLUS,x; increment color table again?
	beq End_Update_Title_Scroll
	ldy TITLE_COLOR_COUNTER
	iny ; next index in color table
	cpy #43 ; 42 is last color index for title colors.
	bne ?Update_Color_Counter 
	ldy #0
?Update_Color_Counter	
	sty TITLE_COLOR_COUNTER

End_Update_Title_Scroll	
	rts


.local
;=============================================
; Erase the Title text from the Title lines.
Clear_Title_Lines
	lda #0 ; clear/blank space
	ldx #7 ; 8 characters in title
Clear_Title_Char
	ldy TITLE_TEXT_CHAR_POS,x ; Get character offset
	sta TITLE_LINE0,y  ; clear first line
	sta TITLE_LINE1,y  ; clear second line
	dex
	bpl Clear_Title_Char
	
	rts


;	.include "dli.asm"
;===============================================================================
; ****    **      ******  
; ** **   **        **   
; **  **  **        **   
; **  **  **        **   
; ** **   **        **   
; ****    ******  ******  
;===============================================================================

DISPLAY_LIST_INTERRUPT

; Do the color bars in the scrolling title text.
; Since the line scrolls, the beginning of the color
; bars changes.  Also, the number of visible scan
; lines of the title changes as the title scrolls
; up.  The VBI maintains the reference for these
; so the DLI doesn't have to figure out anything.

DLI_1 ; Save registers
	pha
	txa
	pha
	tya
	pha

	ldy TITLE_WSYNC_OFFSET ; Number of lines to skip above the text

	beq DLI_Color_Bars ; no lines to skip; do color bars.

DLI_Delay_Top
	sty WSYNC
	dey
	bne DLI_Delay_Top

	; This used to have a lot of junk including value testing
	; to figure out how to color the Player/flying character.
	; However, giving the player a permanent page 0 pointer to
	; a color table (ZTITLE_COLPM0) and having the VBI decide
	; which to use simplified this logic considerably.

DLI_Color_Bars
	ldx TITLE_WSYNC_COLOR ; Number of lines in color bars.

	beq End_DLI_1 ; No lines, so the DLI is finished.

	ldy TITLE_COLOR_COUNTER

	; Here's to hoping that the badline is short enough to allow
	; the player color and four playfield color registers to change 
	; before they are displayed.  This is part of the reason 
	; for the narrow playfield.
DLI_Loop_Color_Bars
	lda (ZTITLE_COLPM0),y ; Set by VBI to point at one of the COLPF tables
	sta WSYNC
	sta COLPM0

	lda TITLE_COLPF0,y
	sta COLPF0

	lda TITLE_COLPF1,y
	sta COLPF1

	lda TITLE_COLPF2,y
	sta COLPF2

	lda TITLE_COLPF3,y
	sta COLPF3

	iny
	dex
	bne DLI_Loop_Color_Bars

End_DLI_1 ; End of routine.  Point to next routine.
	lda #<DLI_2
	sta VDSLST
	lda #>DLI_2
	sta VDSLST+1
	
	pla ; Restore registers for exit
	tay
	pla
	tax
	pla

	rti



DLI_2
	pha
	txa
	pha
	tya
	pha

	; GTIA Fifth Player.
	lda #[FIFTH_PLAYER|1] ; Missiles = COLPF3.  Player/Missiles Priority on top.
	sta PRIOR
	sta HITCLR

	; Screen parameters...
	lda #[ENABLE_DL_DMA|ENABLE_PM_DMA|PLAYFIELD_WIDTH_NORMAL|PM_1LINE_RESOLUTION]
	STA WSYNC
	sta DMACTL

	; Top thumper-bumper.  Only set color.  The rest of the animation is
	; done in the Display list and set by the VBI.
;	lda THUMPER_COLOR_TOP
;	sta COLPF0

	; Left thumper-bumper -- Player 3. P/M color, position, and size.
;	lda THUMPER_COLOR_LEFT
;	sta COLPM3

;	ldy THUMPER_FRAME_LEFT        ; Get animation frame
;	lda THUMPER_LEFT_HPOS_TABLE,y ; P/M position
;	sta HPOSP3
;	lda THUMPER_LEFT_SIZE_TABLE,y ; P/M size
;	sta SIZEP3

	; Right thumper-bumper -- Missile 0.  Set P/M color, position, and size.
;	lda THUMPER_COLOR_RIGHT
;	sta COLPF3 ; because 5th player is enabled.

;	ldy THUMPER_FRAME_RIGHT        ; Get animation frame
;	lda THUMPER_RIGHT_HPOS_TABLE,y ; P/M position
;	sta HPOSM0
;	lda THUMPER_RIGHT_SIZE_TABLE,y ; P/M size
;	sta SIZEM




;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================
	lda #0
	ldy #$E0
	sty WSYNC
	sty CHBASE
	sta COLPF1
	lda #$0A
	sta COLPF2
	



End_DLI_2 ; End of routine.  Point to next routine.
	lda #<DLI_1
	sta VDSLST
	lda #>DLI_1
	sta VDSLST+1

	pla
	tay
	pla
	tax
	pla

	rti




.local	
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

DIAG_TEMP1 = PARAM_89 ; = $d0 ; DIAG_TEMP1

;---------------------------------------------------------------------
; Write hex value of a byte to the DIAG1 screen line.
; INPUT:
; A = byte to write
; Y = starting position.
;---------------------------------------------------------------------
DiagByte

	sta DIAG_TEMP1       ; store the byte to retrieve later

	saveRegs ; Save regs so this is non-disruptive to caller

	lda DIAG_TEMP1
	
	lsr  ; divide by 16 to shift it into the low nybble ( value of 0-F)
	lsr
	lsr
	lsr
	tax 
	lda ?NYBBLE_TO_HEX,x  ; simplify. no math. just lookup table.

	sta DIAG1,y
	
	lda DIAG_TEMP1       ; re-fetch the byte to display

	and #$0F             ; low nybble is second character
	tax
	lda ?NYBBLE_TO_HEX,x  ; simplify. no math.  just lookup table.

	iny
	sta DIAG1,y

	safeRTS ; restore regs for safe exit

?NYBBLE_TO_HEX ; hex binary values 0 - F in internal format
	.sbyte "0123456789ABCDEF"

	
	.macro mDebugByte  ; Address, Y position
		.if %0<>2
			.error "DebugByte: incorrect number of arguments. 2 required!"
		.else
			lda %1
			ldy #%2
			jsr DiagByte
		.endif
	.endm

	
.local
;===============================================================================
; **   **   **    ******  **  **
; *** ***  ****     **    *** **
; ******* **  **    **    ******
; ** * ** **  **    **    ******
; **   ** ******    **    ** ***
; **   ** **  **  ******  **  ** 
;===============================================================================

;===============================================================================
;   MAIN GAME CONTROL LOOP
;===============================================================================

;===============================================================================
; Program Start/Entry.  This address goes in the DOS Run Address.
;===============================================================================

PRG_START 

	jsr Setup  ; setup graphics

	jsr Set_VBI
	
	jsr WaitFrame
	
	lda #1
	jsr MainSetTitle

;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================
	
FOREVER
	
	jsr WaitFrame
	
;	.sbyte " SG PL TM HP VS CS CF WO WC CC DP "
	
	mDebugByte TITLE_STOP_GO,         1 ; SG
	
	mDebugByte TITLE_PLAYING,         4 ; PL

	mDebugByte TITLE_TIMER,           7 ; TM
	
	mDebugByte TITLE_HPOSP0,         10 ; HP

;	mDebugByte TITLE_SIZEP0,         13 ; SP
	
;	mDebugByte TITLE_GPRIOR,         13 ; GP
	
	mDebugByte TITLE_VSCROLL,        13 ; VS
	
	mDebugByte TITLE_CSCROLL,        16 ; CS
	
	mDebugByte TITLE_CURRENT_FLYIN,  19 ; CF
	
	mDebugByte TITLE_SCROLL_COUNTER, 22 ; SC
	
	mDebugByte TITLE_WSYNC_OFFSET,   25 ; WO
	
	mDebugByte TITLE_WSYNC_COLOR,    28 ; WC
	
	mDebugByte TITLE_COLOR_COUNTER,  31 ; CC

	mDebugByte TITLE_DLI_PMCOLOR,    34 ; DP
	
	
	jmp FOREVER



.local
;===============================================================================
;   Basic setup. Stop sound. Create screen.
;===============================================================================

Setup
; Make sure 6502 decimal mode is not set -- not  necessary, 
; but it makes me feel better to know this is not on.
	cld

; Before we can really get going, Atari needs to set up a custom 
; screen to imitate what is being used on the C64.

;;	jsr AtariStopScreen ; Kill screen DMA, kill interrupts, kill P/M graphics.

	lda #0
	sta SDMCTL ; Display DMA control
	
	sta TITLE_HPOSP0    ; reset horizontal position for Player as Title character

	ldx #7
?Zero_PM_HPOS  ; 0 to 7, horizontal position registers for P0-3, M0-3.
	sta HPOSP0,x
	dex
	bpl ?Zero_PM_HPOS
	
	sta GPRIOR

	sta GRACTL ; Graphics Control, P/M DMA 

	lda #PM_SIZE_NORMAL ; reset size for Player as Title character 
	sta SIZEP0

	lda #NMI_VBI
	sta NMIEN
	
;===============================================================================
	jsr WaitFrame ; Wait for vertical blank updates from the shadow registers.
;===============================================================================

;;	jsr AtariStartScreen ; Startup custom display list, etc.
	
	lda #<DISPLAY_LIST ; Display List
	sta SDLSTL
	lda #>DISPLAY_LIST
	sta SDLSTH
	
	lda #<DISPLAY_LIST_INTERRUPT ; DLI Vector
	sta VDSLST
	lda #>DISPLAY_LIST_INTERRUPT
	sta VDSLST+1
	;
	; Turn on Display List DMA
	; Turn on Player/Missile DMA
	; Set Playfield Width Narrow (a temporary thing for the title section)
	; Set Player/Missile DMA to 1 Scan line resolution/updates
	;
	lda #[ENABLE_DL_DMA|ENABLE_PM_DMA|PLAYFIELD_WIDTH_NARROW|PM_1LINE_RESOLUTION]
	sta SDMCTL ; Display DMA control
	
	lda #>PLAYER_MISSILE_BASE ; Player/Missile graphics memory.
	sta PMBASE
	
	lda TITLE_HPOSP0    ; reset horizontal position for Player as Title character
	sta HPOSP0
	
	lda #PM_SIZE_NORMAL ; reset size for Player as Title character 
	sta SIZEP0
	;
	; Set Missiles = 5th Player (COLPF3)
	; Set Priority with Players/Missiles on top
	;
	lda #[FIFTH_PLAYER|1]  
	sta GPRIOR

	lda #[ENABLE_PLAYERS|ENABLE_MISSILES]
	sta GRACTL ; Graphics Control, P/M DMA 

	lda #[NMI_DLI|NMI_VBI] ; Set DLI and VBI Interrupt flags ON
	sta NMIEN
	
	lda #4 ; Finescrolling. 
	sta HSCROL      ; Title text line is shifted by HSCROLL to center it.
	lda #0
	sta VSCROL

	lda #>CHARACTER_SET_01 ; Character set for title
	sta CHBASE
	
;	ldx #$FF
;?Copy_Charset_to_PM
;	lda $e008,x
;	sta PMADR_BASE0,x
;	dex
;	bne ?Copy_Charset_to_PM
	
;	lda #$0F
;	sta COLPM0
	 
	rts 

   

.local
;===============================================================================
; **   **   **    ******  **  **
; *** ***  ****     **    *** **
; ******* **  **    **    ******
; ** * ** **  **    **    ******
; **   ** ******    **    ** ***
; **   ** **  **  ******  **  ** 
;===============================================================================

;===============================================================================
; MAIN SET TITLE
;===============================================================================
; Turn on/off the Title animation.
;===============================================================================
; Input:
; A = Value to write to TITLE_STOP_GO
;===============================================================================
; Set flag referenced by VBI to start/stop animation of the Title line.
;===============================================================================

MainSetTitle

	sta TITLE_STOP_GO
	
	rts


;-------------------------------------------------------------------------------------------
; VBL WAIT
;-------------------------------------------------------------------------------------------
; The Atari OS  maintains a clock that ticks every vertical 
; blank.  So, when the clock ticks the frame has started.

WaitFrame

	lda RTCLOK60			;; get frame/jiffy counter
WaitTick60
	cmp RTCLOK60			;; Loop until the clock changes
	beq WaitTick60

	;; if the real-time clock has ticked off approx 29 seconds,  
	;; then set flag to notify other code.
;	lda RTCLOK+1;
;	cmp #7	;; Has 29 sec timer passed?
;	bne skip_29secTick ;; No.  So don't flag the event.
;	inc auto_next	;; flag the 29 second wait
;	jsr reset_timer

skip_29secTick

;	lda mr_roboto ;; in auto play mode?
;	bne exit_waitFrame ;; Yes. then exit to skip playing sound.

	lda #$00  ;; When Mr Roboto is NOT running turn off the "attract"
	sta ATRACT ;; mode color cycling for CRT anti-burn-in
    
;	jsr AtariSoundService ;; Play sound in progress if any.

exit_waitFrame
	rts


;===============================================================================
;   DISPLAY RELATED MEMORY
;===============================================================================
; This is loaded last, because it defines several large blocks and
; repeatedly forces (re)alignment to Page and K boundaries.
;


;   .include "display.asm"
;===============================================================================
; ****    ******   ****   *****   **        **    **  **  
; ** **     **    **      **  **  **       ****   **  ** 
; **  **    **     ****   **  **  **      **  **   ****  
; **  **    **        **  *****   **      **  **    **   
; ** **     **        **  **      **      ******    **   
; ****    ******   ****   **      ******  **  **    **   
;===============================================================================


;===============================================================================
; PLAYER/MISSILE BITMAP MEMORY
;===============================================================================

	*=$8000

; Using 2K boundary for single-line 
; resolution Player/Missiles
PLAYER_MISSILE_BASE
PMADR_MISSILE = [PLAYER_MISSILE_BASE+$300]
PMADR_BASE0 =   [PLAYER_MISSILE_BASE+$400]
PMADR_BASE1 =   [PLAYER_MISSILE_BASE+$500]
PMADR_BASE2 =   [PLAYER_MISSILE_BASE+$600]
PMADR_BASE3 =   [PLAYER_MISSILE_BASE+$700]

; Align to the boundary after Player/missile bitmaps
; ( *= $8800 )
	*=[*&$F800]+$0800

; Custom character set for Credit text window
; Mode 3 Custom character set. 1024 bytes
; Alphas, numbers, basic punctuation.
; - ( ) . , : ; and /
; Also, infinity and Cross.
; Also artifact "FIRE"

; Character set is 1K of data, so alignment does 
; not need to be forced here.
; ( *= $8C00 )
CHARACTER_SET_00
	.incbin "mode3.cset"


; Custom character set for Title and Score
; Mode 6 custom character set.  512 bytes.
; 2x chars for 0 to 9. 1-10 (top) and 11-20 (bottom)
; 2x chars for title text:  
; B R E A K O U T $15-$24 (top/bottom interleaved)
; 3 chars for ball counter label "BALLS" ($25-$27)

; Character set is 1/2K of data, so
; alignment does not need to be forced here.
; ( *= $8E00 )
CHARACTER_SET_01
	.incbin "breakout.cset"



;===============================================================================
; SCREEN MEMORY -- Directly displayed memory
;===============================================================================

; ( *= $8C00 to $8DFF )
; Real Playfield Memory:  2 pages.
; Aligning inside page boundaries means
; scrolling will only need to update the 
; LMS low byte for every line
;


; ( *= $8E00 to $8E7F )
; Memory for scrolling title
;
TITLE_LINE0
;	.sbyte " o U o U o U o U o U o U o U o U o U o U o U o U o U o U o U o U"
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$0200
TITLE_LINE1
;	.sbyte " o U o U o U o U o U o U o U o U o U o U o U o U o U o U o U o U"
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$0240



; ( *= $8F00 to $8F3F )
; Master copies (source copied to working screen)
;
EMPTY_LINE ; 64 bytes of 0.
	.dc $0040 $00 ; 64 bytes of 0.                  Relative +$0300


;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

DIAG0
	.sbyte " SG PL TM HP VS CS CF SC WO WC CC DP    "

DIAG1
	.dc 40 $00
	


;===============================================================================
; ****    ******   ****   *****   **        **    **  **  
; ** **     **    **      **  **  **       ****   **  ** 
; **  **    **     ****   **  **  **      **  **   ****  
; **  **    **        **  *****   **      **  **    **   
; ** **     **        **  **      **      ******    **   
; ****    ******   ****   **      ******  **  **    **   
;===============================================================================

;===============================================================================
; NOT SCREEN MEMORY (parts copied to screen RAM)
;===============================================================================



; I want the Display List Subroutines to start aligned 
; to a page for the same reason -- This gives them all 
; the same address high byte, so only the low byte
; of the address needs to be changed on JMP instructions
; to target a different subroutine.
	*=[*&$FF00]+$0100
	
; ( *= $9200 to ??????????????$91AC )  (3 * 15 == 45 bytes) 

; Title Frames for coarse scrolling
;
TITLE_FRAME0
; Scan line 9-16,    screen lines 2-9,      Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word EMPTY_LINE
; Scan line 17-24,   screen lines 10-17,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word EMPTY_LINE
; Scan line 25-32,   screen lines 18-25,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [TITLE_LINE0+20] ; Text is at +22.  HSCROLL=4 to center text
; Scan line 33-40,   screen lines 26-33,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [TITLE_LINE1+20]
; Scan line 41,      screen lines 34,       8 (1) blank lines, No scrolling -- sacrifice line
	.byte DL_BLANK_8|DL_DLI ; DLI for Horizontal Thumper Bumper
; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_TITLE_RTS
	
TITLE_FRAME1
; Scan line 9-16,    screen lines 2-9,      Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word EMPTY_LINE
; Scan line 17-24,   screen lines 10-17,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [TITLE_LINE0+20]
; Scan line 25-32,   screen lines 18-25,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [TITLE_LINE1+20]
; Scan line 33-40,   screen lines 26-33,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word EMPTY_LINE
; Scan line 41,      screen lines 34,       8 (1) blank lines, No scrolling -- sacrifice line
	.byte DL_BLANK_8|DL_DLI ; DLI for Horizontal Thumper Bumper
; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_TITLE_RTS

TITLE_FRAME2
; Scan line 9-16,    screen lines 2-9,      Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [TITLE_LINE0+20]
; Scan line 17-24,   screen lines 10-17,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [TITLE_LINE1+20]
; Scan line 25-32,   screen lines 18-25,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word EMPTY_LINE
; Scan line 33-40,   screen lines 26-33,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word EMPTY_LINE
; Scan line 41,      screen lines 34,       8 (1) blank lines, No scrolling -- sacrifice line
	.byte DL_BLANK_8|DL_DLI ; DLI for Horizontal Thumper Bumper
; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_TITLE_RTS

TITLE_FRAME3
; Scan line 9-16,    screen lines 2-9,      Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [TITLE_LINE1+20]
; Scan line 17-24,   screen lines 10-17,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word EMPTY_LINE
; Scan line 25-32,   screen lines 18-25,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word EMPTY_LINE
; Scan line 33-40,   screen lines 26-33,    Mode 6 text, scrolling
	.byte DL_TEXT_6|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word EMPTY_LINE
; Scan line 41,      screen lines 34,       8 (1) blank lines, No scrolling -- sacrifice line
	.byte DL_BLANK_8|DL_DLI ; DLI for Horizontal Thumper Bumper
; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_TITLE_RTS

TITLE_FRAME_EMPTY
; Scan line 9-16,    screen lines 2-9,      Eight blank lines
	.byte DL_BLANK_8
; Scan line 17-24,   screen lines 10-17,    Eight blank lines
	.byte DL_BLANK_8
; Scan line 25-32,   screen lines 18-25,    Eight blank lines
	.byte DL_BLANK_8
; Scan line 33-40,   screen lines 26-33,    Eight blank lines
	.byte DL_BLANK_8
; Scan line 41,      screen lines 34,       1 blank lines, (mimic the scrolling sacrifice)
	.byte DL_BLANK_1|DL_DLI ; DLI for Horizontal Thumper Bumper
; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_TITLE_RTS





	

; A VBI sets initial values:
; HPOS and SIZE for all Players and missiles.
; HSCROL and VSCROL.
; By default CHBAS and inital COLPF/COLPM are already handled.

;===============================================================================
; DISPLAY DESIGN 
;===============================================================================

;-------------------------------------------
; TITLE SECTION: NARROW
; Player 0 == Flying text.
; Mode 6 color text for title.
; Color 0 == Text
; Color 1 == Text
; Color 2 == Text
; Color 3 == Text
;-------------------------------------------
; COLPM0, COLPF0, COLPF1, COLPF2, COLPF3
; HPOSP0
; SIZEP0
; CHBASE
; VSCROLL, HSCROLL (for centering)
;-------------------------------------------
	; Scan line 8,       screen line 1,         One blank scan line

; Jump to Title Scroll frame...

	; Scan lines 9-41,   screen lines 2-34,     4 lines of Mode 6 text for vertical scrolling title 

; Jump back to Main list.

;-------------------------------------------
; THUMPER BUMPER SECTION: NORMAL
; color 1 = horizontal/top bumper.
; Player 3 = Left bumper 
; Missile (5th Player) = Right Bumper
;-------------------------------------------
; COLPF0, COLPM0, COLPF3
; HPOSP3, HPOSM0
; SIZEP3, SIZEM0
;-------------------------------------------

	; Scan line 42,      screen line 35,         One blank scan lines

; Jump to Horizontal Thumper bumper

	; Scan lines 43-53,  screen line 36-46,     11 various blank and graphics lines in routine

; Jump back to Main list.

;-------------------------------------------
; PLAYFIELD SECTION: NORMAL
; color 1 = bricks
; Player 0 = Ball 
; Player 1 = boom-o-matic animation 1
; Player 2 = boom-o-matic animation 1
;-------------------------------------------
;    and already set earlier:
; Player 3 = Left bumper 
; Missile 0 (5th Player) = Right Bumper
;-------------------------------------------
; COLPF0, COLPM0, COLPM1, COLPM2
; HPOSP0, HPOSP1, HPOSP2
; SIZEP0, SIZEP1, SIZEP2
; VSCROLL
;-------------------------------------------

; Blanks above bricks.

	; Scan line 54-77,   screen line 47-70,     24 blank lines

; Bricks...
	; Scan line 78-82,   screen line 71-75,     5 Mode C lines, repeated
	; Scan line 83-84    screen line 76-77,     Two blank scan lines, No scrolling -- sacrifice line
	; ...
	; Brick line 8
	; Scan line 127-131, screen line 120-124,   5 Mode C lines, repeated
	; Scan line 132-133, screen line 125-126,   Two blank scan lines, No scrolling -- sacrifice line

; After Bricks.
	; Scan line 134-141, screen line 127-134,   Eight blank scan lines

;-------------------------------------------
; CREDITS SECTION: NARROW
; Color 2 = text
; Color 3 = text background
;    and already set earlier:
; Player 0 = Ball 
; Player 3 = Left bumper 
; Missile (5th Player) = Right Bumper
;-------------------------------------------
; COLPF1, COLPF2
; CHBASE
; VSCROLL, HSCROLL
;-------------------------------------------

; Credits
	; Scan line 142-151, screen line 135-144,   10 Lines Mode 3
	; Scan line 152-161, screen line 145-154,   10 Lines Mode 3
	; Scan line 162-171, screen line 155-164,   10 Lines Mode 3
	; Scan line 172-181, screen line 165-174,   10 Lines Mode 3
	; Scan line 182-191, screen line 175-184,   10 Lines Mode 3
	; Scan line 192-201, screen line 185-194,   10 Lines Mode 3
	; Scan line 202-202, screen line 195-195,   10 (1) Lines Mode 3 ; scrolling sacrifice
	
	; Scan line 203-204, screen line 196-197,   Two blank scan lines

;-------------------------------------------
; PADDLE SECTION: NARROW
; Player 1 = Paddle
; Player 2 = Paddle
; Player 3 = Paddle
;    and already set earlier:
; Player 0 = Ball 
;-------------------------------------------
; COLPM1, COLPM2, COLPM3
;-------------------------------------------

; Paddle
	; Scan line 205-212, screen line 198-205,   Eight blank scan lines (top 4 are paddle)	

;-------------------------------------------
; SCORE SECTION: NORMAL
; Player 0 == Sine Wave Balls
; Player 1 == Sine Wave Balls
; Player 2 == Sine Wave Balls.
; Player 3 == Sine Wave Balls
; Missile 0 == Sine Wave Balls
; Mode 6 color text for score.
; Color 1  == "BALLS" 
; Color 2  == score
; Color 3  == score
;-------------------------------------------
; COLPM0, COLPF0, COLPF1, COLPF2, COLPF3
; HPOSP0, HPOSP1, HPOSP2, HPOSP3, 
; HPOSM0, HPOSM1, HPOSM2, HPOSM3 
; SIZEP0, SIZEP1, SIZEP2, SIZEP3, SIZEM
; CHBASE
; HSCROLL?
;-------------------------------------------
; Ball counter and score
	; Scan line 213-220, screen line 206-213,   Mode 6 text, scrolling
	; Scan line 221-228, screen line 214-221,   Mode 6 text, scrolling

	; Scan line 229-229, screen line 222-222,   One blank scan line
	
; Jump Vertical Blank.



;===============================================================================
; Forcing the Display list to a 1K boundary 
; is mild overkill.  Display Lists even as funky
; as this one are fairly short. 
; Alignment to the next Page is sufficient insurance 
; preventing the display list from crossing over 
; the next 1K boundary.

	*=[*&$FF00]+$0100

	; ( *= $9300 to  ) 

DISPLAY_LIST 
 
	; Scan line 8,       screen line 1,         One blank scan line
	.byte DL_BLANK_1|DL_DLI 
	; VBI: Set Narrow screen, HSCROLL=4 (to center text), VSCROLL, 
	;      HPOSP0 and SIZE0 for title.  PRIOR=All P/M on top.
	; DLI1: hkernel for COLPF and COLPM color bars in the text.

	.byte DL_JUMP		    ; JMP to Title scrolling display list "routine"
DISPLAY_LIST_TITLE_VECTOR   ; Low byte of coarse scroll frame
	.word TITLE_FRAME_EMPTY ; 

	; DLI2: Occurred as the last line of the Title SCroll section.
	; Set Normal Screen, VSCROLL=0, COLPF0 for horizontal bumper.
	; Set PRIOR for Fifth Player.
	; Set HPOSM0/HPOSM1, COLPF3 SIZEM for left and right Thumper-bumpers.
	; set HITCLR for Playfield.
	; Set HPOSP0/P1/P2, COLPM0/PM1/PM2, SIZEP0/P1/P2 for top row Boom objects.
	
DISPLAY_LIST_TITLE_RTS ; return destination for title scrolling "routine"
	; Scan line 42,      screen line 35,         One blank scan lines
	.byte DL_BLANK_1   ; I am uncomfortable with a JMP going to a JMP.
	; Also, the blank line provides time for clean DLI.
		
	; Scan lines 43-53,  screen line 36-46,     11 various blank and graphics lines in routine


;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

; some blank lines, two lines diagnostics, a few more blank lines.

	.byte $70,$70,$70,$70,$70,$70
	.byte $70,$70,$70,$70,$70,$70
	.byte $42
	.word DIAG0
	.byte $30
	.byte $42
	.word DIAG1
	.byte $70,$70,$70,$70

	; Finito.
	.byte DL_JUMP_VB
	.word DISPLAY_LIST


;===============================================================================
; ****    ******   ****   *****   **        **    **  **  
; ** **     **    **      **  **  **       ****   **  ** 
; **  **    **     ****   **  **  **      **  **   ****  
; **  **    **        **  *****   **      **  **    **   
; ** **     **        **  **      **      ******    **   
; ****    ******   ****   **      ******  **  **    **   
;===============================================================================

; Game Modes.  
; Different sections of the screen are operating at different times.
; 0 = Main title screen.
;     SCrolling title text is OFF.
;     Thumper Bumpers are OFF.  (But they would be off by default over time).
;     BALL is OFF
;     Paddle is off.
; 

;===============================================================================
; ALL THE MOVING PARTS
;===============================================================================
; Tables of things previously declared.
; Tables that don't need alignment.
; Other variables for controlling action/animation and interaction 
; between the display, the VBI, and MAIN.

; Display List Interrupts, Internal Shadow data, and other information.
; Most of this is managed and indexed by the Vertical Blank Interrupt.
; The Display List and Display List Interrupt simply show it as presented.

; Title: Animated text fly-in, the color gradient cycling and scrolling  
; text at top of screen operates during game play, and the pause screen.
; This is Off for Game Over, and Title screens
;
; Two second delay (120) frames for no activity.
; Text flies in from the right 2 color clocks per frame.
; Four second delay (240) frames for viewing.
; Vscroll up 1 scanline until all lines gone.
; 
TITLE_STOP_GO = PARAM_09 
; .byte 0 ; set by mainline to indicate title is working or not.
; 0 = stop.
; 1 = go.  (after main routine has initialized restart).

TITLE_PLAYING = PARAM_10 
; .byte 0 ; flag indicates title animation stage in progress. 
; 0 == not running -- title lines in 0/empty state. 
; 1 == clear. no movement. (Running a couple second of delay.)
; 2 == Text fly-in is in progress. 
; 3 == pause for public admiration. 
; 4 == Text  VSCROLL to top of screen in progress.  return to 0 state.

TITLE_TIMER = PARAM_11
; .byte 0 ; set by Title handler for pauses.

TITLE_HPOSP0 = PARAM_12
; .byte 0 ; Current P/M position of fly-in letter. or 0 if no letter.

TITLE_SIZEP0 = PARAM_13
; .byte PM_SIZE_NORMAL ; current size of Player 0

TITLE_GPRIOR = PARAM_14
; .byte 1 ; Current P/M Priority in title. 

TITLE_VSCROLL = PARAM_15
; .byte 0 ; current fine scroll position. (0 to 7)

TITLE_CSCROLL = PARAM_16
; .byte 0 ; current coarse scroll position. (0 to 4)

; Display List -- Title Scrolling coarse scroll conditions.
;
TITLE_FRAME_TABLE
	.byte <TITLE_FRAME_EMPTY
	.byte <TITLE_FRAME0
	.byte <TITLE_FRAME1
	.byte <TITLE_FRAME2
	.byte <TITLE_FRAME3

TITLE_CURRENT_FLYIN = PARAM_17
; .byte 0 ; current index (0 to 7) into tables for visible stuff in table below.

; Character base offset to data for custom BREAKOUT characters
; is the character set base + $A8.  Use that as starting address 
; and add the following.  Basically a table of Nth character * 16.
TITLE_PM_IMAGE_LIST ; beginning offset into character set to copy image data to Player
	.byte $60,$70,$80,$90,$a0,$b0,$c0,$d0

TITLE_PM_TARGET_LIST ; Player target HPOS
	entry .= 0
	.rept 8 ; repeat for 8 characters
	.byte [PLAYFIELD_LEFT_EDGE_NARROW+4+entry]
	entry .= entry+16 ; next entry in table.
	.endr

; B R E A K O U T custom chars in different COLPF values
TITLE_CHAR_LIST ; Screen byte of first (top) half of each character 
	.byte $21,$23+$40,$25+$80,$27+$C0
	.byte $29,$2b+$40,$2d+$80,$2f+$C0 

TITLE_TEXT_CHAR_POS ; Title Line offset for each character
	.byte 22,24,26,28,30,32,34,36 

; The following tables vertically scroll the title up 
; off the screen.  It has step by step values for 
; VSCROLL, coarse scroll (in display list), WSYNC offset,
; Wsync color, flag to double-increment the color counter.
; While the VSCROLL is always 0,1,2,3,4,5,6,7, it is easier
; to just read from table and store rather than checking 
; for 8, then resetting, and coarse scrolling.
; 32 steps for each.
TITLE_VSCROLL_TABLE
	.byte 0,1,2,3,4,5,6,7
	.byte 0,1,2,3,4,5,6,7
	.byte 0,1,2,3,4,5,6,7
	.byte 0,1,2,3,4,5,6,7

TITLE_CSCROLL_TABLE ; index into TITLE_FRAME_TABLE
	.byte 1,1,1,1,1,1,1,1
	.byte 2,2,2,2,2,2,2,2
	.byte 3,3,3,3,3,3,3,3
	.byte 4,4,4,4,4,4,4,4

TITLE_WSYNC_OFFSET_TABLE ; DLI: Skip lines before starting color bar. 
	.byte 20,19,18,17,16,15,14,13
	.byte 12,11,10,9,8,7,6,5
	.byte 4,3,2,1,0,0,0,0
	.byte 0,0,0,0,0,0,0,0

TITLE_WSYNC_COLOR_TABLE ; DLI: How many lines to read from color tables.
	.byte 12,12,12,12,12,12,12,12
	.byte 12,12,12,12,12,12,12,12
	.byte 12,12,12,12,12,11,10,9
	.byte 8,7,6,5,4,3,2,1

TITLE_COLOR_COUNTER_PLUS ; Flag to double-increment COLOR_COUNTER when losing lines.
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 1,1,1,1,1,1,1,1
	.byte 1,1,1,1,1,1,1,1

TITLE_SCROLL_COUNTER = PARAM_18 
; .byte 0 ; index into the tables above. 0 to 32

; DLI parts.
TITLE_WSYNC_OFFSET = PARAM_19
; .byte 20 ; Number of scan lines to drop through before color draw

TITLE_WSYNC_COLOR = PARAM_20
; .byte 12 ; Number of scan lines to do color bars

TITLE_COLOR_COUNTER = PARAM_21
; .byte 0  ; Index into color table

TITLE_DLI_PMCOLOR = PARAM_22
; .byte 0 ; PM Index into TITLE_DLI_PMCOLOR_TABLE  

TITLE_DLI_PMCOLOR_TABLE ; which text color to use for P/M. referenced by TITLE_CURRENT_FLYIN.
	.byte 0,1,2,3,0,1,2,3

; Which COLPF table should the flying title 
; character as COLPM0 use for color?
; The VBI will assign this to a Page 0 
; location, so the DLI can use indirect 
; address to set the color for the Player.	
TITLE_DLI_COLPM_TABLE_LO
	.byte <TITLE_COLPF0
	.byte <TITLE_COLPF1
	.byte <TITLE_COLPF2
	.byte <TITLE_COLPF3
	
TITLE_DLI_COLPM_TABLE_HI
	.byte >TITLE_COLPF0
	.byte >TITLE_COLPF1
	.byte >TITLE_COLPF2
	.byte >TITLE_COLPF3

; Page 0 location is a pointer to one 
; of the COLPF tables.
ZTITLE_COLPM0=ZEROPAGE_POINTER_9 


TITLE_COLPF0 ; "Red"
	.byte COLOR_PINK+$00 ; 0 ; First 12 positions are start
	.byte COLOR_PINK+$02 ; 1
	.byte COLOR_PINK+$04 ; 2
	.byte COLOR_PINK+$06 ; 3
	.byte COLOR_PINK+$08 ; 4
	.byte COLOR_PINK+$0a ; 5
	.byte COLOR_PINK+$0c ; 6
	.byte COLOR_PINK+$0e ; 7
	.byte COLOR_PINK+$0c ; 8
	.byte COLOR_PINK+$0a ; 9 
	.byte COLOR_PINK+$08 ; 10
	.byte COLOR_PINK+$06 ; 11
	.byte COLOR_PINK+$04 ;(12)
	.byte COLOR_PINK+$02 ;(13)
	.byte COLOR_PINK+$00 ;(14)
	.byte COLOR_PINK+$00 ;(15)
	.byte COLOR_PINK+$02 ;(16)
	.byte COLOR_PINK+$02 ;(17)
	.byte COLOR_PINK+$04 ;(18)
	.byte COLOR_PINK+$04 ;(19)
	.byte COLOR_PINK+$06 ;(20)
	.byte COLOR_PINK+$06 ;(21)
	.byte COLOR_PINK+$08 ;(22)
	.byte COLOR_PINK+$08 ;(23)
	.byte COLOR_PINK+$0a ;(24) 
	.byte COLOR_PINK+$0a ;(25) 
	.byte COLOR_PINK+$0c ;(26) 
	.byte COLOR_PINK+$0c ;(27) 
	.byte COLOR_PINK+$0e ;(28) 
	.byte COLOR_PINK+$0e ;(29) 
	.byte COLOR_PINK+$0c ;(30) 
	.byte COLOR_PINK+$0c ;(31) 
	.byte COLOR_PINK+$0a ;(32) 
	.byte COLOR_PINK+$0a ;(33) 
	.byte COLOR_PINK+$08 ;(34) 
	.byte COLOR_PINK+$08 ;(35) 
	.byte COLOR_PINK+$06 ;(36) 
	.byte COLOR_PINK+$06 ;(37)
	.byte COLOR_PINK+$04 ;(38) 
	.byte COLOR_PINK+$04 ;(39) 
	.byte COLOR_PINK+$02 ;(40)
	.byte COLOR_PINK+$02 ;(41) 
	.byte COLOR_PINK+$00 ;(42) -- end on this index.
	.byte COLOR_PINK+$00 ; 0
	.byte COLOR_PINK+$02 ; 1
	.byte COLOR_PINK+$04 ; 2
	.byte COLOR_PINK+$06 ; 3
	.byte COLOR_PINK+$08 ; 4
	.byte COLOR_PINK+$0a ; 5
	.byte COLOR_PINK+$0c ; 6
	.byte COLOR_PINK+$0e ; 7
	.byte COLOR_PINK+$0c ; 8
	.byte COLOR_PINK+$0a ; 9 
	.byte COLOR_PINK+$08 ; 10

	

TITLE_COLPF1 ; "Orange"
	entry .= $04
	.rept 6 ; repeating for 12 bytes 4, 6, 8, a, c, e
	.byte [COLOR_RED_ORANGE+entry]
	.byte [COLOR_RED_ORANGE+entry]
	entry .= entry+2 ; next entry in table.
	.endr
	.rept 7 ; repeating for 14 bytes c, a, 8, 6, 4, 2, 0
	entry .= entry-2 ; next entry in table.
	.byte [COLOR_RED_ORANGE+entry]
	.byte [COLOR_RED_ORANGE+entry]
	.endr
	.rept 7 ; repeating for 7 bytes 2, 4, 6, 8, a, c, e
	entry .= entry+2 ; next entry in table.
	.byte [COLOR_RED_ORANGE+entry]
	.endr
	.rept 6 ; repeating for 6 bytes c, a, 8, 6, 4, 2
	entry .= entry-2 ; next entry in table.
	.byte [COLOR_RED_ORANGE+entry]
	.endr
	entry .= $00
	.rept 7 ; repeating for 14 bytes 0, 2, 4, 6, 8, a, c
	.byte [COLOR_RED_ORANGE+entry]
	.byte [COLOR_RED_ORANGE+entry]
	entry .= entry+2 ; next entry in table.
	.endr
	.byte COLOR_RED_ORANGE+$0e
; 12 + 14 + 7 + 6 + 14 + 1 == 54 == 43 color lines + 11 dups
	
	
;	.byte COLOR_RED_ORANGE+$04 ; 10
;	.byte COLOR_RED_ORANGE+$04 ; 11
;	.byte COLOR_RED_ORANGE+$06 ;(12)
;	.byte COLOR_RED_ORANGE+$06 ;(13)
;	.byte COLOR_RED_ORANGE+$08 ;(14)
;	.byte COLOR_RED_ORANGE+$08 ;(15)
;	.byte COLOR_RED_ORANGE+$0a ;(16)
;	.byte COLOR_RED_ORANGE+$0a ;(17)
;	.byte COLOR_RED_ORANGE+$0c ;(18)
;	.byte COLOR_RED_ORANGE+$0c ;(19)
;	.byte COLOR_RED_ORANGE+$0e ;(20)
;	.byte COLOR_RED_ORANGE+$0e ;(21)--
	
;	.byte COLOR_RED_ORANGE+$0c ;(22)
;	.byte COLOR_RED_ORANGE+$0c ;(23)
;	.byte COLOR_RED_ORANGE+$0a ;(24) 
;	.byte COLOR_RED_ORANGE+$0a ;(25) 
;	.byte COLOR_RED_ORANGE+$08 ;(26) 
;	.byte COLOR_RED_ORANGE+$08 ;(27) 
;	.byte COLOR_RED_ORANGE+$06 ;(28) 
;	.byte COLOR_RED_ORANGE+$06 ;(29) 
;	.byte COLOR_RED_ORANGE+$04 ;(30) 
;	.byte COLOR_RED_ORANGE+$04 ;(31) 
;	.byte COLOR_RED_ORANGE+$02 ;(32) 
;	.byte COLOR_RED_ORANGE+$02 ;(33) 
;	.byte COLOR_RED_ORANGE+$00 ;(34) 
;	.byte COLOR_RED_ORANGE+$00 ;(35)
	
;	.byte COLOR_RED_ORANGE+$02 ;(36) 
;	.byte COLOR_RED_ORANGE+$04 ;(37)
;	.byte COLOR_RED_ORANGE+$06 ;(38) 
;	.byte COLOR_RED_ORANGE+$08 ;(39) 
;	.byte COLOR_RED_ORANGE+$0a ;(40)
;	.byte COLOR_RED_ORANGE+$0c ;(41) 
;	.byte COLOR_RED_ORANGE+$0e ;(42)
	
;	.byte COLOR_RED_ORANGE+$0c ; 0
;	.byte COLOR_RED_ORANGE+$0a ; 1
;	.byte COLOR_RED_ORANGE+$08 ; 2
;	.byte COLOR_RED_ORANGE+$06 ; 3
;	.byte COLOR_RED_ORANGE+$04 ; 4
;	.byte COLOR_RED_ORANGE+$02 ; 5
	
;	.byte COLOR_RED_ORANGE+$00 ; 6
;	.byte COLOR_RED_ORANGE+$00 ; 7
;	.byte COLOR_RED_ORANGE+$02 ; 8
;	.byte COLOR_RED_ORANGE+$02 ; 9 -- end on this index.
;	.byte COLOR_RED_ORANGE+$04 ; 10  
;	.byte COLOR_RED_ORANGE+$04 ; 0 ; First 12 positions are start
;	.byte COLOR_RED_ORANGE+$06 ; 1
;	.byte COLOR_RED_ORANGE+$06 ; 2
;	.byte COLOR_RED_ORANGE+$08 ; 3
;	.byte COLOR_RED_ORANGE+$08 ; 4
;	.byte COLOR_RED_ORANGE+$0a ; 5
;	.byte COLOR_RED_ORANGE+$0a ; 6
;	.byte COLOR_RED_ORANGE+$0c ; 7
;	.byte COLOR_RED_ORANGE+$0c ; 8

;	.byte COLOR_RED_ORANGE+$0e ; 9 

; Fit of extreme laziness.   
; Just Copy/Paste sections from the top to the bottom. 
TITLE_COLPF2 ; "Green"
	.byte COLOR_GREEN+$08 ;(18)
	.byte COLOR_GREEN+$06 ;(19)
	.byte COLOR_GREEN+$04 ;(20)
	.byte COLOR_GREEN+$02 ;(21)
	.byte COLOR_GREEN+$00 ;(22)
	.byte COLOR_GREEN+$00 ;(23)
	.byte COLOR_GREEN+$02 ;(24) 
	.byte COLOR_GREEN+$02 ;(25) 
	.byte COLOR_GREEN+$04 ;(26) 
	.byte COLOR_GREEN+$04 ;(27) 
	.byte COLOR_GREEN+$06 ;(28) 
	.byte COLOR_GREEN+$06 ;(29) 
	.byte COLOR_GREEN+$08 ;(30) 
	.byte COLOR_GREEN+$08 ;(31) 
	.byte COLOR_GREEN+$0a ;(32) 
	.byte COLOR_GREEN+$0a ;(33) 
	.byte COLOR_GREEN+$0c ;(34) 
	.byte COLOR_GREEN+$0c ;(35) 
	.byte COLOR_GREEN+$0e ;(36) 
	.byte COLOR_GREEN+$0e ;(37)
	.byte COLOR_GREEN+$0c ;(38) 
	.byte COLOR_GREEN+$0c ;(39) 
	.byte COLOR_GREEN+$0a ;(40)
	.byte COLOR_GREEN+$0a ;(41) 
	.byte COLOR_GREEN+$08 ;(42) 
	.byte COLOR_GREEN+$08 ; 0
	.byte COLOR_GREEN+$06 ; 1
	.byte COLOR_GREEN+$06 ; 2
	.byte COLOR_GREEN+$04 ; 3
	.byte COLOR_GREEN+$04 ; 4
	.byte COLOR_GREEN+$02 ; 5
	.byte COLOR_GREEN+$02 ; 6
	.byte COLOR_GREEN+$00 ; 7
	.byte COLOR_GREEN+$00 ; 8
	.byte COLOR_GREEN+$02 ; 9 
	.byte COLOR_GREEN+$04 ; 10
	.byte COLOR_GREEN+$06 ; 0 ; First 12 positions are start
	.byte COLOR_GREEN+$08 ; 1
	.byte COLOR_GREEN+$0a ; 2
	.byte COLOR_GREEN+$0c ; 3
	.byte COLOR_GREEN+$0e ; 4
	.byte COLOR_GREEN+$0c ; 5
	.byte COLOR_GREEN+$0a ; 6 -- end on this index.
	.byte COLOR_GREEN+$08 ; 7
	.byte COLOR_GREEN+$06 ; 8
	.byte COLOR_GREEN+$04 ; 9 
	.byte COLOR_GREEN+$02 ; 10
	.byte COLOR_GREEN+$00 ; 11
	.byte COLOR_GREEN+$00 ;(12)
	.byte COLOR_GREEN+$02 ;(13)
	.byte COLOR_GREEN+$02 ;(14)
	.byte COLOR_GREEN+$04 ;(15)
	.byte COLOR_GREEN+$04 ;(16)
	.byte COLOR_GREEN+$06 ;(17)

	
TITLE_COLPF3 ; "Yellow"
	.byte COLOR_LITE_ORANGE+$0c ;(30) 
	.byte COLOR_LITE_ORANGE+$0c ;(31) 
	.byte COLOR_LITE_ORANGE+$0a ;(32) 
	.byte COLOR_LITE_ORANGE+$0a ;(33) 
	.byte COLOR_LITE_ORANGE+$08 ;(34) 
	.byte COLOR_LITE_ORANGE+$08 ;(35) 
	.byte COLOR_LITE_ORANGE+$06 ;(36) 
	.byte COLOR_LITE_ORANGE+$06 ;(37)
	.byte COLOR_LITE_ORANGE+$04 ;(38) 
	.byte COLOR_LITE_ORANGE+$04 ;(39) 
	.byte COLOR_LITE_ORANGE+$02 ;(40)
	.byte COLOR_LITE_ORANGE+$02 ;(41) 
	.byte COLOR_LITE_ORANGE+$00 ;(42) 
	.byte COLOR_LITE_ORANGE+$00 ; 0
	.byte COLOR_LITE_ORANGE+$02 ; 1
	.byte COLOR_LITE_ORANGE+$04 ; 2
	.byte COLOR_LITE_ORANGE+$06 ; 3
	.byte COLOR_LITE_ORANGE+$08 ; 4
	.byte COLOR_LITE_ORANGE+$0a ; 5
	.byte COLOR_LITE_ORANGE+$0c ; 6
	.byte COLOR_LITE_ORANGE+$0e ; 7
	.byte COLOR_LITE_ORANGE+$0c ; 8
	.byte COLOR_LITE_ORANGE+$0a ; 9 
	.byte COLOR_LITE_ORANGE+$08 ; 10
	.byte COLOR_LITE_ORANGE+$06 ; 0 ; First 12 positions are start
	.byte COLOR_LITE_ORANGE+$04 ; 1
	.byte COLOR_LITE_ORANGE+$02 ; 2
	.byte COLOR_LITE_ORANGE+$00 ; 3
	.byte COLOR_LITE_ORANGE+$00 ; 4
	.byte COLOR_LITE_ORANGE+$02 ; 5
	.byte COLOR_LITE_ORANGE+$02 ; 6
	.byte COLOR_LITE_ORANGE+$04 ; 7
	.byte COLOR_LITE_ORANGE+$04 ; 8
	.byte COLOR_LITE_ORANGE+$06 ; 9 
	.byte COLOR_LITE_ORANGE+$06 ; 10
	.byte COLOR_LITE_ORANGE+$08 ; 11
	.byte COLOR_LITE_ORANGE+$08 ;(12)
	.byte COLOR_LITE_ORANGE+$0a ;(13)
	.byte COLOR_LITE_ORANGE+$0a ;(14)
	.byte COLOR_LITE_ORANGE+$0c ;(15)
	.byte COLOR_LITE_ORANGE+$0c ;(16)
	.byte COLOR_LITE_ORANGE+$0e ;(17)
	.byte COLOR_LITE_ORANGE+$0e ;(18) -- end on this index.
	.byte COLOR_LITE_ORANGE+$0c ;(19)
	.byte COLOR_LITE_ORANGE+$0c ;(20)
	.byte COLOR_LITE_ORANGE+$0a ;(21)
	.byte COLOR_LITE_ORANGE+$0a ;(22)
	.byte COLOR_LITE_ORANGE+$08 ;(23)
	.byte COLOR_LITE_ORANGE+$08 ;(24) 
	.byte COLOR_LITE_ORANGE+$06 ;(25) 
	.byte COLOR_LITE_ORANGE+$06 ;(26) 
	.byte COLOR_LITE_ORANGE+$04 ;(27) 
	.byte COLOR_LITE_ORANGE+$04 ;(28) 
	.byte COLOR_LITE_ORANGE+$02 ;(29) 




;===============================================================================
;   PROGRAM_INIT_ADDRESS
;===============================================================================
; Atari uses a structured executable file format that 
; loads data to specific memory and provides an automatic 
; run address.
;===============================================================================
; Store the program start location in the Atari DOS RUN Address.
; When DOS is done loading the executable it will automatically
; jump to the address placed in the DOS_RUN_ADDR.
;===============================================================================
;
	*=DOS_RUN_ADDR
	.word PRG_START

;===============================================================================

	.end ; finito
 
;===============================================================================

