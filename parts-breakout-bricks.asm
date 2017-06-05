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
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

	.macro mDebugByte  ; Address, Y position
		.if %0<>2
			.error "DebugByte: incorrect number of arguments. 2 required!"
		.else
			lda %1
			ldy #%2
			jsr DiagByte
		.endif
	.endm


	
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

MIN_PIXEL_Y = 55 ; Top edge of the playfield.  just a guess right now.
MAX_PIXEL_Y = 224 ; bottom edge after paddle.  lose ball here.

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
;    PAGE ZERO VARIABLES
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


;===============================================================================
PARAM_80 = $c7 ; TITLE_SLOW_ME_CLOCK - frame clock to slow title stages. 
;===============================================================================
PARAM_81 = $c8 ; TITLE_COLOR_COUNTER_CLOCK - frame clock to slow color gradient
PARAM_82 = $c9 ; ENABLE_THUMPER - should have thought of this earlier.
PARAM_83 = $ca ;    
PARAM_84 = $cb ; 
PARAM_85 = $cc ;    
PARAM_86 = $cd ; 
PARAM_87 = $ce ; 
PARAM_88 = $cf ; 
PARAM_89 = $d0 ; 
PARAM_90 = $d1 ; 
PARAM_91 = $d2 ;
PARAM_92 = $d3 ; DIAG_SLOW_ME_CLOCK
PARAM_93 = $d5 ; DIAG_TEMP1

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
;   DECLARE VALUES AND ADDRESS ASSIGNMENTS (NOT ALLOCATING MEMORY)
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


ZBRICK_BASE =   ZEROPAGE_POINTER_8 ; $EC - Pointer to start of bricks on a line.

ZTITLE_COLPM0 = ZEROPAGE_POINTER_9 ; $EE - VBI sets for DLI to use



;===============================================================================
; ****    ******   ****   *****   **        **    **  **   ****
; ** **     **    **      **  **  **       ****   **  **  **  **
; **  **    **     ****   **  **  **      **  **   ****   ** ***
; **  **    **        **  *****   **      **  **    **    *** **
; ** **     **        **  **      **      ******    **    **  **
; ****    ******   ****   **      ******  **  **    **     ****
;===============================================================================

;===============================================================================
; MOVING PARTS
;===============================================================================

; DISPLAY values using Page 0 locations.


; ==============================================================
; BRICKS
; ==============================================================
; "Bricks" refers to the playfield bricks and 
; the graphics for the Title log and the Game
; Over screen.  "Bricks" may also be an empty
; line to remove/transition these objects between
; the different displays.
;
; The Bricks may be in a static state for maintaining 
; current contents, or in a transition state 
; moving another screen contents on to the display.
;
; The MAIN code preps the BRICK lines for movement,
; sets the direction of each, and then notifies the 
; VBI to make the updates.

;===============================================================================
; BRICKS/PLAYFIELD -- HORIZONTAL SCROLL
;===============================================================================
; The playfield area is used for the game bricks while playing 
; and the large blocks for the TITLE LOGO and the GAME OVER.
;
; Lets talk about horizontal fine scrolling on the Atari...
;
; Earlier, the BRICK_LINEs were defined as 64-bytes each. 
; Part of the reason for this is to make the address math easy
; for the rows.   The other part has to do with how horizontal
; scrolling works.
;
; The graphics mode for the BRICKS is 20 bytes for normal screen 
; width (at 8 color clocks per byte). The game needs three screens 
; next to each other to accommodate the transitions.  (Well, it 
; could actually be done as 2 screens next to each other by someone 
; more clever. It is easier for my feeble mind to manage it if the 
; apparent transition motion between three screens really is 
; three screens.)
;
; The screen arrangement per line:
; 20 bytes|20 bytes|20 bytes == 60 bytes.
;
; To make the screens look like the end of one screen isn't 
; directly attached to the start of the next, I insert
; one empty byte between each:
; 20 bytes|1 byte|20 bytes|1 byte|20 bytes == 62 bytes.
;
; So, the program can just use the first 62 bytes of each row, and
; ignore the last two, right? Not so. The program must offset its 
; base reference for the three screens due to the way the Atari 
; does horizontal scrolling. 
;
; When horizontal scrolling is enabled ANTIC reads more data beginning
; at the current memory scan address than it needs to display the
; visible graphics line -- it reads enough additional data to 
; maintain a buffer of 16 color clocks at the beginning of the 
; display line.
;
; Examples below assume a graphics mode that displays 8 color clocks 
; (pixels) per byte (the mode used for the game playfield.):
;
; Normal memory read and display:
; (Simple and obvious -- 20 bytes read. 20 bytes displayed) 
; P is displayed pixels from a byte
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3 ...|byte 18 |byte 19 |
; |PPPPPPPP|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|
; 
; Memory read and display for Horizontal scrolling:
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BBBBBBBB|BBBBBBBB|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|
;   FEDCBA9|87654321|0 = HSCROL positions
;                    ^ HSCROL = 0
;
; Horizontal scrolling works by using the HSCROL register to specify
; how many of the 16 buffered color clocks at the start of the line 
; should be output for display.  The example above shows none of the 
; buffered pixels output, so the HSCROL value is 0. Note that in this 
; case of HSCROL value 0 the buffer causes the actual display output to 
; begin two bytes later in memory than specified by ANTIC's memory scan 
; pointer.  

; The HSCROL value may range from 0 buffered color clocks output to 
; display up to 15 buffered color clocks output.  The example below 
; shows HSCROL set to 3.
;
; Memory read and display for Horizontal scrolling when HSCROL = 3
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is previously displayable pixels removed from display due to HSCROL shifting the pixels.
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BBBBBBBB|BBBBBDDD|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPNNN|
;   FEDCBA9|87654321|0 = HSCROL positions
;                ^ HSCROL = 3
;
; The number of color clocks output for display is still consistent with the 
; normal output for the mode of graphics.   The contents of the line 
; shifts to the right "losing" 3 color clocks at the right side of the screen
; while HSCROL adds 3 color clocks to the left side of the display.
;
; Note that while ANTIC buffers 16 color clocks of data, the HSCROL value can 
; only range up to 15.  This means the first buffered color clock is not
; displayable...
;
; Memory read and display for Horizontal scrolling when HSCROL = 15 ($F)
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is previously displayable pixels removed from display due to HSCROL shifting the pixels.
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BDDDDDDD|DDDDDDDD|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PNNNNNNN|NNNNNNNN|
; | FEDCBA9|87654321|0 = HSCROL positions
; | ^ HSCROL = 15 ($F)
;  
; Displaying that final color clock requires (at least) one more byte prior 
; to this byte allowing HSCROL to output the contents of this byte.
; In other words, begin displaying from a previous memory location 
; (the original byte 0 address - 2 bytes) and then set fine scroll HSCROL 
; value to 0.
;
; An interesting part of Atari horizontal scrolling is that the 16 color 
; clocks buffered can exceed the distance of one byte's worth of color clocks.
; Therefore the increment (or decrement) for coarse scrolling is greater than 
; 1 byte. Some ANTIC modes have two bytes per 16 color clocks, some have 
; 4 bytes.  This has the interesting effect that the same display can be output 
; by different variations of memory scan starting address and HSCROL.
; For example, the display output is identical for the two settings below:
; 
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is pixels not displayed on right.
; Z is pixels not read/not buffered/not displayed from the left 
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |byte 22 |
; |BBBBBBBB|BBBBBBBB|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|NNNNNNNN|
; | FEDCBA9|87654321|0 = HSCROL positions
; |                  ^ HSCROL = 0
;
; MS (memory scan pointer points to byte 1)
;           v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |byte 22 |
; |ZZZZZZZZ|BBBBBBBB|DDDDDDDD|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|NNNNNNNN|
; |        | FEDCBA9|87654321|0 = HSCROL positions
; |                  ^ HSCROL = 8
;
; So, the consequence of this discussion and horizontal scrolling's treatment of the 
; first byte of the buffer means that the program can't consider the first byte 
; completely displayable and will ignore it as part of the intended display output.  
; However, the program must still accommodate that byte in order to scroll to the 
; byte that follows. 
;
; Therefore, the memory map for the display lines looks like this: 
; ignore byte 0|20 bytes|1 byte|20 bytes|1 byte|20 bytes == 63 bytes.
;
; Thus the origination position for each of the three screens relative to the 
; base address of each line:
; Left Screen: Memory Scan +0,  HSCROL = 8
; Center Screen: Memory Scan +20, HSCROL = 0 (or Memory Scan +21, HSCROL = 8)
; Right Screen: Memory Scan +41, HSCROL = 0 (or Memory Scan +42, HSCROL = 8)
;
; Reference lookup for Display List LMS offset for screen postition:
; 0 = left
; 1 = center
; 2 = right
;
;
; MAIN flag to VBI requesting start of screen transition.
;
BRICK_SCREEN_START_SCROLL = PARAM_35
; .byte 0
;
; MAIN signal to move immediately to target positions if value is 1.
; Copy the BRICK_BRICK_SCREEN_TARGET_LMS_LMS and 
; BRICK_SCREEN_TARGET_HSCROL to all current positions.
;
BRICK_SCREEN_IMMEDIATE_POSITION = PARAM_36
; .byte 0
;
; VBI Feedback to MAIN that it is busy moving
;
BRICK_SCREEN_IN_MOTION = PARAM_37
; .byte 0
;



;===============================================================================
; ****   ******   **    *****   ****
; ** **    **    ****  **      **  **
; **  **   **   **  ** **      ** ***
; **  **   **   **  ** ** ***  *** **
; ** **    **   ****** **  **  **  **
; ****   ****** **  **  *****   ****
;===============================================================================

DIAG_SLOW_ME_CLOCK = PARAM_92 ; = $d3 ; DIAG_SLOW_ME_CLOCK

DIAG_TEMP1 = PARAM_93 ; = $d5 ; DIAG_TEMP1



;===============================================================================
;   INITIALIZE ZERO PAGE VALUES
;===============================================================================

    *= BRICK_SCREEN_START_SCROLL ; and BRICK_SCREEN_IMMEDIATE_POSITION and BRICK_SCREEN_IN_MOTION
    .byte 0,0,0
    

    





;===============================================================================
;   LOAD START
;===============================================================================

;	*=LOMEM_DOS     ; $2000  ; After Atari DOS 2.0s
;	*=LOMEM_DOS_DUP ; $3308  ; Alternatively, after Atari DOS 2.0s and DUP

; This will not be a terribly big or complicated game.  Begin after DUP.
; Will be changed in a moment when alignment is set Player/Missile memory.

	*=$3308    

;===============================================================================

;===============================================================================
;   DISPLAY RELATED MEMORY
;===============================================================================
; This defines several large blocks and repeatedly forces 
; (re)alignment to Page and K boundaries.
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

;	*=$8000

	*=[*&$F800]+$0800
	
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

BRICK_LINE0 
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$0000
BRICK_LINE1
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$0040
BRICK_LINE2
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$0080
BRICK_LINE3
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$00C0
BRICK_LINE4
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$0100
BRICK_LINE5
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$0140
BRICK_LINE6
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$0180
BRICK_LINE7
	.dc $0040 $00 ; 64 bytes for left/right scroll. Relative +$01C0




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
	.sbyte " XT XL XR FT FL FR LT LL LR CT CL CR    "

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


; ( *= $8F54 to $8F67 ) 20 bytes
; 14 bricks, 11 pixels each, 154 pixels total. 
; Centered in 160 pixels.
; Bricks start at pixel 3 (counting from 0.
; Its easier to figure this out drawing it in binary...
;
BRICK_LINE_MASTER
	.byte ~00011111, ~11111011, ~11111111, ~01111111, ~11101111 ; 0, 1, 2, 3
	.byte ~11111101, ~11111111, ~10111111, ~11110111, ~11111110 ; 3, 4, 5, 6
	.byte ~11111111, ~11011111, ~11111011, ~11111111, ~01111111 ; 7, 8, 9, 10
	.byte ~11101111, ~11111101, ~11111111, ~10111111, ~11110000 ; 10, 11, 12, 13
	

; I want the graphics masters aligned to the start of a page.
; to insure cycling between each line does not require 
; updating a high byte for address.
	*=[*&$FF00]+$0100
	
; ( *= $9000 )  ( 160 bytes == 20 * 8) 
; Logo Picture imitating bricks.  
; Conveniently, 4 pixels/nybble per brick.
; Originally the graphic was 38 Characters wide,
; now as nybble pairs it is 19 characters wide. 
; In order to center this in the Playfield, each
; line is shifted one nybble, to center the data
; in 20 bytes.
;
; ***  ***  **** **   *  * **** *  *I***
; *  * *  * *    * *  *  * *  * *  *  * 
; *  * *  * *    *  * * *  *  * *  *  * 
; ***  ***  ***  **** ***  *  * *  *  * 
; *  * *  * *    *  * *  * *  * *  *  * 
; ** * ** * **   ** * ** * ** * ** *  **
; ** * ** * **   ** * ** * ** * ** *  **
; ***  ** * **** ** * ** * **** ****  **
;
LOGO_LINE0
	.byte $0F,$FF,$00,$FF,$F0,$0F,$FF,$F0,$FF,$00,$0F,$00,$F0,$FF,$FF,$0F,$00,$F3,$FF,$F0
LOGO_LINE1
	.byte $0F,$00,$F0,$F0,$0F,$0F,$00,$00,$F0,$F0,$0F,$00,$F0,$F0,$0F,$0F,$00,$F0,$0F,$00
LOGO_LINE2
	.byte $0F,$00,$F0,$F0,$0F,$0F,$00,$00,$F0,$0F,$0F,$0F,$00,$F0,$0F,$0F,$00,$F0,$0F,$00
LOGO_LINE3
	.byte $0F,$FF,$00,$FF,$F0,$0F,$FF,$00,$FF,$FF,$0F,$FF,$00,$F0,$0F,$0F,$00,$F0,$0F,$00
LOGO_LINE4
	.byte $0F,$00,$F0,$F0,$0F,$0F,$00,$00,$F0,$0F,$0F,$00,$F0,$F0,$0F,$0F,$00,$F0,$0F,$00
LOGO_LINE5
	.byte $0F,$F0,$F0,$FF,$0F,$0F,$F0,$00,$FF,$0F,$0F,$F0,$F0,$FF,$0F,$0F,$F0,$F0,$0F,$F0
LOGO_LINE6
	.byte $0F,$F0,$F0,$FF,$0F,$0F,$F0,$00,$FF,$0F,$0F,$F0,$F0,$FF,$0F,$0F,$F0,$F0,$0F,$F0
LOGO_LINE7
	.byte $0F,$FF,$00,$FF,$0F,$0F,$FF,$F0,$FF,$0F,$0F,$F0,$F0,$FF,$FF,$0F,$FF,$F0,$0F,$F0


; I want the graphics masters aligned to the start of a page.
; to insure cycling between each line does not require 
; updating a high byte for address.
	*=[*&$FF00]+$0100

; ( *= $9100 )  ( 160 bytes == 16 * 8)

; Game Over Picture imitating bricks.  3 pixels per brick,
; because it would not fit with 4 pixels per block.  At 4 pixels
; per brick the text would be 42 blocks which is 168 pixels and 
; the limit is 160 pixels in this mode.  
;
; This is redrawn and reencoded. Converting the picture 
; blocks to 000 or 111 bits worked well, so the representation 
; here is bit format. This is now 3 pixels * 42 block
; which is 126 pixels. Two additional 0 bits added to 
; center this in 128 pixels. Graphics length is 16 bytes.
; two 0 bytes added to the beginning and end of each line
; to center this in 20 bytes.
; 
; **** **   *   * ****   **** *  * **** *** 
; *    * *  ** ** *      *  * *  * *    *  *
; *    *  * * * * *      *  * *  * *    *  *
; * ** **** *   * ***    *  * *  * ***  *** 
; *  * *  * *   * *      *  * *  * *    *  *
; ** * ** * **  * **     ** * ** * **   ** *
; ** * ** * **  * **     ** *  * * **   ** *
; ***  ** * **  * ****   ****   ** **** ** *
;

GAMEOVER_LINE0
	.byte $00,$00,~01111111,~11111000,~11111100,~00000001,~11000000,~00011100,~01111111,~11111000,~00000011,~11111111,~11000111,~00000011,~10001111,~11111111,~00011111,~11110000,$00,$00
GAMEOVER_LINE1
	.byte $00,$00,~01110000,~00000000,~11100011,~10000001,~11111000,~11111100,~01110000,~00000000,~00000011,~10000001,~11000111,~00000011,~10001110,~00000000,~00011100,~00001110,$00,$00
GAMEOVER_LINE2
	.byte $00,$00,~01110000,~00000000,~11100000,~01110001,~11000111,~00011100,~01110000,~00000000,~00000011,~10000001,~11000111,~00000011,~10001110,~00000000,~00011100,~00001110,$00,$00
GAMEOVER_LINE3
	.byte $00,$00,~01110001,~11111000,~11111111,~11110001,~11000000,~00011100,~01111111,~11000000,~00000011,~10000001,~11000111,~00000011,~10001111,~11111000,~00011111,~11110000,$00,$00
GAMEOVER_LINE4
	.byte $00,$00,~01110000,~00111000,~11100000,~01110001,~11000000,~00011100,~01110000,~00000000,~00000011,~10000001,~11000111,~00000011,~10001110,~00000000,~00011100,~00001110,$00,$00
GAMEOVER_LINE5
	.byte $00,$00,~01111110,~00111000,~11111100,~01110001,~11111000,~00011100,~01111110,~00000000,~00000011,~11110001,~11000111,~11100011,~10001111,~11000000,~00011111,~10001110,$00,$00
GAMEOVER_LINE6
	.byte $00,$00,~01111110,~00111000,~11111100,~01110001,~11111000,~00011100,~01111110,~00000000,~00000011,~11110001,~11000000,~11100011,~10001111,~11000000,~00011111,~10001110,$00,$00
GAMEOVER_LINE7
	.byte $00,$00,~01111111,~11000000,~11111100,~01110001,~11111000,~00011100,~01111111,~11111000,~00000011,~11111111,~11000000,~00011111,~10001111,~11111111,~00011111,~10001110,$00,$00








	

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

;===============================================================================

;	.byte DL_JUMP		    ; JMP to Title scrolling display list "routine"

;DISPLAY_LIST_TITLE_VECTOR   ; Low byte of coarse scroll frame
;	.word TITLE_FRAME_EMPTY ; 

;TITLE_FRAME_EMPTY
; Scan line 9-16,    screen lines 2-9,      Eight blank lines
	.byte DL_BLANK_8
; Scan line 17-24,   screen lines 10-17,    Eight blank lines
	.byte DL_BLANK_8
; Scan line 25-32,   screen lines 18-25,    Eight blank lines
	.byte DL_BLANK_8
; Scan line 33-40,   screen lines 26-33,    Eight blank lines
	.byte DL_BLANK_8
; Scan line 41,      screen lines 34,       1 blank lines, (mimic the scrolling sacrifice)
	.byte DL_BLANK_1|DL_DLI ; DLI2 for Horizontal Thumper Bumper
; Return to main display list
;	.byte DL_JUMP
;	.word DISPLAY_LIST_TITLE_RTS

;===============================================================================

	; DLI2: Occurred as the last line of the Title SCroll section.
	; Set Normal Screen, VSCROLL=0, COLPF0 for horizontal bumper.
	; Set PRIOR for Fifth Player.
	; Set HPOSM0/HPOSM1, COLPF3 SIZEM for left and right Thumper-bumpers.
	; set HITCLR for Playfield.
	; Set HPOSP0/P1/P2, COLPM0/PM1/PM2, SIZEP0/P1/P2 for top row Boom objects.
	
;DISPLAY_LIST_TITLE_RTS ; return destination for title scrolling "routine"
	; Scan line 42,      screen line 35,         One blank scan lines
	.byte DL_BLANK_1   ; I am uncomfortable with a JMP going to a JMP.
	; Also, the blank line provides time for clean DLI.
		
	; Scan lines 43-53,  screen line 36-46,     11 various blank and graphics lines in routine

	
;	.byte DL_JUMP	        ; Jump to horizontal thumper animation frame
DISPLAY_LIST_THUMPER_VECTOR ; remember this -- update low byte to change frames
;	.word THUMPER_FRAME_WAIT

;   Simulate the thumper box.

    .byte DL_BLANK_3
    .byte DL_BLANK_8
    
	; Note DLI started before thumper-bumper Display Lists for 
	; P/M HPOS, COLPM, SIZE and HITCLR
	; Also, this DLI ends by setting HPOS and COLPM for the BOOM 
	; objects in the top row of bricks. 

DISPLAY_LIST_THUMPER_RTS ; destination for animation routine return.
	; Top of Playfield is empty above the bricks. 
	; Scan line 54-77,   screen line 47-70,     24 blank lines


	.byte DL_BLANK_8
	.byte DL_BLANK_8
	.byte DL_BLANK_7|DL_DLI 
	.byte DL_BLANK_1
	; DLI3: Hkernel 8 times....
	;      Set HSCROLL for line, VSCROLL = 5, then Set COLPF0 for 5 lines.
	;      Reset VScroll to 1 (allowing 2 blank lines.)
	;      Set P/M Boom objects, HPOS, COLPM, SIZE
	;      Repeat HKernel.

	; Define 8 rows of Bricks.  
	; Each is 5 lines of mode C graphics, plus 2 blank line.
	; The 5 rows of graphics are defined by using the VSCROL
	; exploit to expand one line of mode C into five lines.

	; Block line 1
	; Scan line 78-82,   screen line 71-75,     5 Mode C lines, repeated
	; Scan line 83-84    screen line 76-77,     Two blank scan lines, No scrolling -- sacrifice line
	; ...
	; Block line 8
	; Scan line 127-131, screen line 120-124,   5 Mode C lines, repeated
	; Scan line 132-133, screen line 125-126,   Two blank scan lines, No scrolling -- sacrifice line
BRICK_BASE
	; BRICK_BASE+1, +5, +9, +13, +17, +21, +25, +29 is low byte of row.
	; Only this byte should be needed for scrolling each row.
	entry .= 0
	.rept 8 ; repeat for 8 lines of bricks (56 scan lines) 
	; scan line +0 to +4  -- 5 scan lines of mode C copied/extended

	.byte DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
	.word [GAMEOVER_LINE0+[entry*20]-2] 

;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]
;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]
;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]
;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]
;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]

	; two blank scan line
	.byte DL_BLANK_2
	entry .= entry+1 ; next entry in table.
	.endr
	; HKernel ends:
	; set Narrow screen, COLPF2, VSCROLL, COLPF1 for scrolling credit/prompt window.
	; Collect HITCLR values for analysis of bricks .  Reset HITCLR.
	
	; a scrolling window for messages and credits.  
	; This is 8 blank lines +  8 * 10 scan lines plus 7 blank lines.
	; These are ANTIC Mode 3 lines so each is 10 scan lines tall.




;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

; some blank lines, two lines diagnostics, a few more blank lines.


	.byte $70,$70,$F0,$70 ; Last DLI for DIAG
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

; Non-aligned variables and data.

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











; ==============================================================
; BRICKS
; ==============================================================
; "Bricks" refers to the playfield bricks and 
; the graphics for the Title log and the Game
; Over screen.  "Bricks" may also be an empty
; line to remove/transition these objects between
; the different displays.
;
; The Bricks may be in a static state for maintaining 
; current contents, or in a transition state 
; moving another screen contents on to the display.
;
; The MAIN code preps the BRICK lines for movement,
; sets the direction of each, and then notifies the 
; VBI to make the updates.

;===============================================================================
; BRICKS/PLAYFIELD -- HORIZONTAL SCROLL
;===============================================================================
; The playfield area is used for the game bricks while playing 
; and the large blocks for the TITLE LOGO and the GAME OVER.
;
; Lets talk about horizontal fine scrolling on the Atari...
;
; Earlier, the BRICK_LINEs were defined as 64-bytes each. 
; Part of the reason for this is to make the address math easy
; for the rows.   The other part has to do with how horizontal
; scrolling works.
;
; The graphics mode for the BRICKS is 20 bytes for normal screen 
; width (at 8 color clocks per byte). The game needs three screens 
; next to each other to accommodate the transitions.  (Well, it 
; could actually be done as 2 screens next to each other by someone 
; more clever. It is easier for my feeble mind to manage it if the 
; apparent transition motion between three screens really is 
; three screens.)
;
; The screen arrangement per line:
; 20 bytes|20 bytes|20 bytes == 60 bytes.
;
; To make the screens look like the end of one screen isn't 
; directly attached to the start of the next, I insert
; one empty byte between each:
; 20 bytes|1 byte|20 bytes|1 byte|20 bytes == 62 bytes.
;
; So, the program can just use the first 62 bytes of each row, and
; ignore the last two, right? Not so. The program must offset its 
; base reference for the three screens due to the way the Atari 
; does horizontal scrolling. 
;
; When horizontal scrolling is enabled ANTIC reads more data beginning
; at the current memory scan address than it needs to display the
; visible graphics line -- it reads enough additional data to 
; maintain a buffer of 16 color clocks at the beginning of the 
; display line.
;
; Examples below assume a graphics mode that displays 8 color clocks 
; (pixels) per byte (the mode used for the game playfield.):
;
; Normal memory read and display:
; (Simple and obvious -- 20 bytes read. 20 bytes displayed) 
; P is displayed pixels from a byte
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3 ...|byte 18 |byte 19 |
; |PPPPPPPP|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|
; 
; Memory read and display for Horizontal scrolling:
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BBBBBBBB|BBBBBBBB|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|
;   FEDCBA9|87654321|0 = HSCROL positions
;                    ^ HSCROL = 0
;
; Horizontal scrolling works by using the HSCROL register to specify
; how many of the 16 buffered color clocks at the start of the line 
; should be output for display.  The example above shows none of the 
; buffered pixels output, so the HSCROL value is 0. Note that in this 
; case of HSCROL value 0 the buffer causes the actual display output to 
; begin two bytes later in memory than specified by ANTIC's memory scan 
; pointer.  

; The HSCROL value may range from 0 buffered color clocks output to 
; display up to 15 buffered color clocks output.  The example below 
; shows HSCROL set to 3.
;
; Memory read and display for Horizontal scrolling when HSCROL = 3
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is previously displayable pixels removed from display due to HSCROL shifting the pixels.
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BBBBBBBB|BBBBBDDD|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPNNN|
;   FEDCBA9|87654321|0 = HSCROL positions
;                ^ HSCROL = 3
;
; The number of color clocks output for display is still consistent with the 
; normal output for the mode of graphics.   The contents of the line 
; shifts to the right "losing" 3 color clocks at the right side of the screen
; while HSCROL adds 3 color clocks to the left side of the display.
;
; Note that while ANTIC buffers 16 color clocks of data, the HSCROL value can 
; only range up to 15.  This means the first buffered color clock is not
; displayable...
;
; Memory read and display for Horizontal scrolling when HSCROL = 15 ($F)
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is previously displayable pixels removed from display due to HSCROL shifting the pixels.
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BDDDDDDD|DDDDDDDD|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PNNNNNNN|NNNNNNNN|
; | FEDCBA9|87654321|0 = HSCROL positions
; | ^ HSCROL = 15 ($F)
;  
; Displaying that final color clock requires (at least) one more byte prior 
; to this byte allowing HSCROL to output the contents of this byte.
; In other words, begin displaying from a previous memory location 
; (the original byte 0 address - 2 bytes) and then set fine scroll HSCROL 
; value to 0.
;
; An interesting part of Atari horizontal scrolling is that the 16 color 
; clocks buffered can exceed the distance of one byte's worth of color clocks.
; Therefore the increment (or decrement) for coarse scrolling is greater than 
; 1 byte. Some ANTIC modes have two bytes per 16 color clocks, some have 
; 4 bytes.  This has the interesting effect that the same display can be output 
; by different variations of memory scan starting address and HSCROL.
; For example, the display output is identical for the two settings below:
; 
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is pixels not displayed on right.
; Z is pixels not read/not buffered/not displayed from the left 
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |byte 22 |
; |BBBBBBBB|BBBBBBBB|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|NNNNNNNN|
; | FEDCBA9|87654321|0 = HSCROL positions
; |                  ^ HSCROL = 0
;
; MS (memory scan pointer points to byte 1)
;           v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |byte 22 |
; |ZZZZZZZZ|BBBBBBBB|DDDDDDDD|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|NNNNNNNN|
; |        | FEDCBA9|87654321|0 = HSCROL positions
; |                  ^ HSCROL = 8
;
; So, the consequence of this discussion and horizontal scrolling's treatment of the 
; first byte of the buffer means that the program can't consider the first byte 
; completely displayable and will ignore it as part of the intended display output.  
; However, the program must still accommodate that byte in order to scroll to the 
; byte that follows. 
;
; Therefore, the memory map for the display lines looks like this: 
; ignore byte 0|20 bytes|1 byte|20 bytes|1 byte|20 bytes == 63 bytes.
;
; Thus the origination position for each of the three screens relative to the 
; base address of each line:
; Left Screen: Memory Scan +0,  HSCROL = 8
; Center Screen: Memory Scan +20, HSCROL = 0 (or Memory Scan +21, HSCROL = 8)
; Right Screen: Memory Scan +41, HSCROL = 0 (or Memory Scan +42, HSCROL = 8)
;
; Reference lookup for Display List LMS offset for screen postition:
; 0 = left
; 1 = center
; 2 = right
;
BRICK_SCREEN_LMS  
	.byte 0,20,41
;
; and HSCROL value to align the correct bytes...
;
BRICK_SCREEN_HSCROL 
	.byte 8,0,0
;
; Offsets of Display List LMS pointers (low byte) of each row position.
; BRICK_BASE+1, +5, +9, +13, +17, +21, +25, +29 is low byte of row.
; DISPLAY LIST: offset from BRICK_BASE to low byte of each LMS address
BRICK_LMS_OFFSETS 
	.byte 1,5,9,13,17,21,25,29
;
; DLI: HSCROL/fine scrolling position.
;
BRICK_CURRENT_HSCROL 
	.byte 0,0,0,0,0,0,0,0
;
; DLI: Set line colors....  introducing a little more variety than 
; the original game and elsewhere on the screen.
;
BRICK_CURRENT_COLOR ; Base color for gradients
	.byte COLOR_PINK+2,        COLOR_PURPLE+2,     
	.byte COLOR_RED_ORANGE+2,  COLOR_ORANGE2+2
	.byte COLOR_GREEN+2,       COLOR_BLUE_GREEN+2, 
	.byte COLOR_LITE_ORANGE+2, COLOR_ORANGE_GREEN+2
;
; MAIN code sets the following sets of configuration
; per each line of the playfield.  VBI takes these
; instructions and moves display during each frame.
;
; Target LMS offset/coarse scroll to move the display. 
; One target per display line... line 0 to line 7.
;
BRICK_SCREEN_TARGET_LMS 
	.byte 20,20,20,20,20,20,20,20
;
; Target HSCROL/fine scrolling destination for moving display.
;
BRICK_SCREEN_TARGET_HSCROL 
	.byte 0,0,0,0,0,0,0,0
;
; Increment or decrement the movement direction? 
; -1=view Left/graphics right, +1=view Right/graphics left
;
BRICK_SCREEN_DIRECTION 
	.byte 1,$FF,1,$FF,1,$FF,1,$FF
;
; Table of patterns-in-a-can for direction....
;
TABLE_CANNED_BRICK_DIRECTIONS ; random(8) * 8
	.byte 1,1,1,1,1,1,1,1          ; all view Right/graphics left
	.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; all view Left/graphics right 
	.byte 1,1,1,1,$FF,$FF,$FF,$FF      ; top go Right, Bottom go Left
	.byte $FF,$FF,$FF,$FF,1,1,1,1      ; top go Left, Bottom go Right
	.byte 1,1,$FF,$FF,1,1,$FF,$FF      ; 2 go right, 2 go left, etc.
	.byte $FF,$FF,1,1,$FF,$FF,1,1      ; 2 go left, 2 go right, etc.
	.byte 1,$FF,1,$FF,1,$FF,1,$FF      ; right, left, right, left...
	.byte $FF,1,$FF,1,$FF,1,$FF,1      ; left, right, left, right...
;
; Brick scroll speed (HSCROLs +/- per frame).
; Note, that row 8 MUST ALWAYS be the fastest/max speed
; to insure the bottom row of bricks are in place before 
; the ball returns to collide with the bricks.
;
BRICK_SCREEN_HSCROL_MOVE 
	.byte 1,1,2,2,3,3,4,4
;
; Table of patterns-in-a-can for scroll speed....
;
TABLE_CANNED_BRICK_SPEED ; random(4) * 8
	.byte 4,4,4,4,4,4,4,4 ; Block move fastest
	.byte 1,1,2,2,3,3,4,4 ; Top slowest, bottom fastest.
	.byte 1,2,3,4,1,2,3,4 ; Two, slow-to-fast gradients.
	.byte 4,3,2,1,1,2,3,4 ; Center slowest, outside fastest. 
;
; Frame count to delay start of scroll movement.
; Note, that row 8 MUST ALWAYS be 0 to insure the bottom 
; row of bricks are in place before the ball returns to 
; collide with the bricks.
;
BRICK_SCREEN_MOVE_DELAY 
	.byte 7,6,5,4,3,2,1,0
;
; Table of patterns-in-a-can for delaying start of scroll.
; Note that a custom delay is chosen ONLY when the scroll
; DIRECTION is 1 or 0,  and the SPEED 0.
;
TABLE_CANNED_BRICKS_DELAY
	.byte 0,0,0,0,0,0,0,0         ; No Delay.
	.byte 30,30,20,20,10,10,0,0   ; 1/2 second gradient pairs
	.byte 60,60,40,40,20,20,0,0   ; 1 second gradient pairs
	.byte 120,120,80,80,40,40,0,0 ; 2 second gradient pairs 
	.byte 14,12,10,8,6,4,2,0      ; two frames each
	.byte 56,48,40,32,24,16,8,0   ; 8 frames each
	.byte 0,10,20,30,30,20,10,0   ; 1/2 second top/bottom gradient
	.byte 40,20,30,70,120,20,60,0 ; 2 second randomish 
;
; MAIN flag to VBI requesting start of screen transition.
;
BRICK_SCREEN_START_SCROLL = PARAM_35
; .byte 0
;
; MAIN signal to move immediately to target positions if value is 1.
; Copy the BRICK_BRICK_SCREEN_TARGET_LMS_LMS and 
; BRICK_SCREEN_TARGET_HSCROL to all current positions.
;
BRICK_SCREEN_IMMEDIATE_POSITION = PARAM_36
; .byte 0
;
; VBI Feedback to MAIN that it is busy moving
;
BRICK_SCREEN_IN_MOTION = PARAM_37
; .byte 0
;
; Table of starting addresses for each line. 
;
BRICK_LINE_TABLE_LO
	entry .= 0
	.rept 8 ; repeat for 8 lines
	.byte <[BRICK_LINE0+[entry*64]]
	entry .= entry+1 ; next entry in table.
	.endr
	
BRICK_LINE_TABLE_HI
	entry .= 0
	.rept 8 ; repeat for 8 lines
	.byte >[BRICK_LINE0+[entry*64]]
	entry .= entry+1 ; next entry in table.
	.endr
;
; Base location of visible bricks (in the middle of the line)
;
BRICK_BASE_LINE_TABLE_LO
	entry .= 0
	.rept 8 ; repeat for 8 lines
	.byte <[BRICK_LINE0+[entry*64]+21]
	entry .= entry+1 ; next entry in table.
	.endr
	

	
BRICK_BASE_LINE_TABLE_HI
	entry .= 0
	.rept 8 ; repeat for 8 lines
	.byte >[BRICK_LINE0+[entry*64]+21]
	entry .= entry+1 ; next entry in table.
	.endr

;
; Mask to erase an individual brick, numbered 0 to 13.
; Starting byte offset for visible screen memory, then the AND mask 
; for 3 bytes because some bricks cross three bytes.
;
BRICK_MASK_TABLE
	.byte $00, ~00000000, ~00000011, ~11111111
	.byte $01, ~11111000, ~00000000, ~01111111
	.byte $03, ~00000000, ~00001111, ~11111111
	.byte $04, ~11100000, ~00000001, ~11111111

	.byte $05, ~11111100, ~00000000, ~00111111
	.byte $07, ~10000000, ~00000111, ~11111111
	.byte $08, ~11110000, ~00000000, ~11111111
	.byte $0a, ~00000000, ~00011111, ~11111111

	.byte $0b, ~11000000, ~00000011, ~11111111
	.byte $0c, ~11111000, ~00000000, ~01111111
	.byte $0e, ~00000000, ~00001111, ~11111111
	.byte $0f, ~11100000, ~00000001, ~11111111

	.byte $10, ~11111100, ~00000000, ~00111111
	.byte $12, ~10000000, ~00000000, ~00000000  ; This would also clear byte 21
;
; Test an individual brick, numbered 0 to 13.
; Starting byte offset for visible screen memory, then the AND mask 
; for 3 bytes because some bricks cross three bytes.
; If anything reports as 1 then a pric is present.
; (Almost the same as BRICK_MASK_TABLE EOR $FF)
;
BRICK_TEST_TABLE
	.byte $00, ~00011111, ~11111000, ~00000000
	.byte $01, ~00000011, ~11111111, ~00000000
	.byte $03, ~01111111, ~11100000, ~00000000
	.byte $04, ~00001111, ~11111100, ~00000000

	.byte $05, ~00000001, ~11111111, ~10000000
	.byte $07, ~00111111, ~11110000, ~00000000
	.byte $08, ~00000111, ~11111110, ~00000000
	.byte $0a, ~11111111, ~11000000, ~00000000

	.byte $0b, ~00011111, ~11111000, ~00000000
	.byte $0c, ~00000011, ~11111111, ~00000000
	.byte $0e, ~01111111, ~11100000, ~00000000
	.byte $0f, ~00001111, ~11111100, ~00000000

	.byte $10, ~00000001, ~11111111, ~10000000
	.byte $12, ~00111111, ~11110000, ~00000000


;
; Table for P/M Xpos of each brick left edge
;
BRICK_XPOS_LEFT_TABLE
	entry .= 0
	.rept 14 ; repeat for 14 bricks in a line
	.byte [PLAYFIELD_LEFT_EDGE_NORMAL+BRICK_LEFT_OFFSET+[entry*BRICK_WIDTH]]
	entry .= entry+1 ; next entry in table.
	.endr
;
; Table for P/M Xpos of each brick right edge
;
BRICK_XPOS_RIGHT_TABLE
	entry .= 0
	.rept 14 ; repeat for 14 bricks in a line
	.byte [PLAYFIELD_LEFT_EDGE_NORMAL+BRICK_RIGHT_OFFSET+[entry*BRICK_WIDTH]]
	entry .= entry+1 ; next entry in table.
	.endr


; The "PLAYFIELD edge offset" for Y direction defined in the  
; custom chip include files is not used here, because the vertical 
; display is entirely managed by a custom display list instead of 
; the default Operating System graphics modes.
;
; Table for P/M Ypos of each brick top edge
;
BRICK_YPOS_TOP_TABLE
	entry .= 0
	.rept 8 ; repeat for 8 lines of bricks 
	.byte [BRICK_TOP_OFFSET+[entry*BRICK_HEIGHT]]
	entry .= entry+1 ; next entry in table.
	.endr
;
; Table for P/M Ypos of each brick bottom edge
;
BRICK_YPOS_BOTTOM_TABLE
	entry .= 0
	.rept 8 ; repeat for 8 lines of bricks 
	.byte [BRICK_BOTTOM_OFFSET+[entry*BRICK_HEIGHT]]
	entry .= entry+1 ; next entry in table.
	.endr


; BRICK_BASE+1, +5, +9, +13, +17, +21, +25, +29 is low byte of row.

;BRICK_LINE_MASTER
;	.byte ~00011111, ~11111011, ~11111111, ~01111111, ~11101111 ; 0, 1, 2, 3
;	.byte ~11111101, ~11111111, ~10111111, ~11110111, ~11111110 ; 3, 4, 5, 6
;	.byte ~11111111, ~11011111, ~11111011, ~11111111, ~01111111 ; 7, 8, 9, 10
;	.byte ~11101111, ~11111101, ~11111111, ~10111111, ~11110000 ; 10, 11, 12, 13


; Convert X coordinate to brick, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14.
; The Table does NOT contain entries for the entire playfield width.  It contains
; only the entries of the valid playfield from left bumper to right bumper.
; Three color clocks on the left and four on the right are not included in the 
; playfield.  
; (or from Normal Border Left Offset +3  to Normal Border Right Offset -4).
;
; The 11-ness of the brick width is what makes calculations a bear.  And this would
; have to be repeated for every pixel test for multiple position tests per each frame. 
; A lookup table reduces this computation to an indexed read.  
;
; Still this table is a highly wasteful 153 byte travesty. 

BALL_XPOS_TO_BRICK_TABLE
	.byte 1,1,1,1,1,1,1,1,1,1,0
	.byte 2,2,2,2,2,2,2,2,2,2,0
	.byte 3,3,3,3,3,3,3,3,3,3,0
	.byte 4,4,4,4,4,4,4,4,4,4,0
	.byte 5,5,5,5,5,5,5,5,5,5,0
	.byte 6,6,6,6,6,6,6,6,6,6,0
	.byte 7,7,7,7,7,7,7,7,7,7,0
	.byte 8,8,8,8,8,8,8,8,8,8,0
	.byte 9,9,9,9,9,9,9,9,9,9,0
	.byte 10,10,10,10,10,10,10,10,10,10,0
	.byte 11,11,11,11,11,11,11,11,11,11,0
	.byte 12,12,12,12,12,12,12,12,12,12,0
	.byte 13,13,13,13,13,13,13,13,13,13,0
	.byte 14,14,14,14,14,14,14,14,14,14

; Brick rows are 5 lines + 2 blanks between.  Another bad computation like
; the X Position deal.  When the Ball Y position to test is between the 
; first scan line and last scan line of the brick rows this lookup table
; identifies the row 1, 2, 3, 4, 5, 6, 7, 8.

BALL_YPOS_TO_BRICK_TABLE
	.byte 1,1,1,1,1,0,0
	.byte 2,2,2,2,2,0,0
	.byte 3,3,3,3,3,0,0
	.byte 4,4,4,4,4,0,0
	.byte 5,5,5,5,5,0,0
	.byte 6,6,6,6,6,0,0
	.byte 7,7,7,7,7,0,0
	.byte 8,8,8,8,8


; Other "BRICKS" things...
;
; Pointers to data to draw the Title screen logo
;
LOGO_LINE_TABLE_LO
	entry .= 0
	.rept 8 ; repeat for 8 rows
	.byte <[LOGO_LINE0+[entry*19]]
	entry .= entry+1 ; next entry in table.
	.endr
	
LOGO_LINE_TABLE_HI
	entry .= 0
	.rept 8 ; repeat for 8 rows
	.byte >[LOGO_LINE0+[entry*19]]
	entry .= entry+1 ; next entry in table.
	.endr
;
; Pointers to data to draw the Game Over screen
;
GAMEOVER_LINE_TABLE_LO
	entry .= 0
	.rept 8 ; repeat for 8 rows
	.byte <[GAMEOVER_LINE0+[entry*16]]
	entry .= entry+1 ; next entry in table.
	.endr

GAMEOVER_LINE_TABLE_HI
	entry .= 0
	.rept 8 ; repeat for 8 rows
	.byte >[GAMEOVER_LINE0+[entry*16]]
	entry .= entry+1 ; next entry in table.
	.endr


	
	
	
	
	
	
;===============================================================================
; BOOM-O-MATIC.
;===============================================================================
; Players 1 and 2 implement a Boom animation for bricks knocked out.
; The animation overlays the destroyed brick with a player two scan lines 
; and two color clocks larger than the brick.  This is centered on the brick
; providing a first frame impression that the brick expands. On subsequent 
; frames the image shrinks and color fades. 
;
; A DLI cuts these two players HPOS for each line of bricks, so there are 
; two separate Boom-o-matics possible for each line.   Realistically, 
; given the ball motion and collision policy it is impossible to request 
; two Boom cycles begin on the same frame for the same row, and would be 
; unlikely to have multiple animations running on every line. (But, just
; in case the code plans for the worst.)
;
; When MAIN code detects collision it will generate a request for a Boom-O-Matic
; animation that VBI will service.  VBI will determine if the request is for
; Boom 1 or Boom 2 .  If both animation cycles are in progress the one with the
; most progress will reset itself for the new animation.
;
; Side note -- maybe a future iteration will utilize the boom-o-matic blocks 
; during Title or Game Over sequences.

ENABLE_BOOM = PARAM_38
; .byte 0

BOOM_1_REQUEST 
	.byte 0,0,0,0,0,0,0,0 ; MAIN provides flag to add this brick. 0 = no brick. 1 = new brick.
BOOM_2_REQUEST 
	.byte 0,0,0,0,0,0,0,0 ; MAIN provides flag to add this brick.

BOOM_1_REQUEST_BRICK 
	.byte 0,0,0,0,0,0,0,0 ; MAIN provides brick number in this row. 0 - 13
BOOM_2_REQUEST_BRICK 
	.byte 0,0,0,0,0,0,0,0 ; MAIN provides brick number in this row. 0 - 13

BOOM_1_CYCLE 
	.byte 0,0,0,0,0,0,0,0 ; VBI needs one for each row (0 = no animation)
BOOM_2_CYCLE 
	.byte 0,0,0,0,0,0,0,0 ; VBI needs one for each row

BOOM_1_BRICK 
	.byte 0,0,0,0,0,0,0,0 ; VBI uses Brick number on the row doing the Boom Cycle.
BOOM_2_BRICK 
	.byte 0,0,0,0,0,0,0,0 ; VBI uses Brick number on the row doing the Boom Cycle.

BOOM_1_HPOS 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs HPOS1 for row
BOOM_2_HPOS 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs HPOS2 for row

BOOM_1_SIZE 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs P/M SIZE1 for row
BOOM_2_SIZE 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs P/M SIZE2 for row

BOOM_1_COLPM 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs P/M COLPM1 for row
BOOM_2_COLPM 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs P/M COLPM2 for row

BOOM_CYCLE_COLOR ; by row by cycle frame -- 9 frames per boom animation
	.byte $0E,COLOR_PINK|$0E,         COLOR_PINK|$0C,         COLOR_PINK|$0A,         COLOR_PINK|$08,         COLOR_PINK|$06,         COLOR_PINK|$04,        $02,$00
	.byte $0E,COLOR_PURPLE|$0E,       COLOR_PURPLE|$0C,       COLOR_PURPLE|$0A,       COLOR_PURPLE|$08,       COLOR_PURPLE|$06,       COLOR_PURPLE|$04,      $02,$00
	.byte $0E,COLOR_RED_ORANGE|$0E,   COLOR_RED_ORANGE|$0C,   COLOR_RED_ORANGE|$0A,   COLOR_RED_ORANGE|$08,   COLOR_RED_ORANGE|$06,   COLOR_RED_ORANGE|$04,  $02,$00
	.byte $0E,COLOR_ORANGE2|$0E,      COLOR_ORANGE2|$0C,      COLOR_ORANGE2|$0A,      COLOR_ORANGE2|$08,      COLOR_ORANGE2|$06,      COLOR_ORANGE2|$04,     $02,$00
	.byte $0E,COLOR_GREEN|$0E,        COLOR_GREEN|$0C,        COLOR_GREEN|$0A,        COLOR_GREEN|$08,        COLOR_GREEN|$06,        COLOR_GREEN|$04,       $02,$00
	.byte $0E,COLOR_BLUE_GREEN|$0E,   COLOR_BLUE_GREEN|$0C,   COLOR_BLUE_GREEN|$0A,   COLOR_BLUE_GREEN|$08,   COLOR_BLUE_GREEN|$06,   COLOR_BLUE_GREEN|$04,  $02,$00
	.byte $0E,COLOR_LITE_ORANGE|$0E,  COLOR_LITE_ORANGE|$0C,  COLOR_LITE_ORANGE|$0A,  COLOR_LITE_ORANGE|$08,  COLOR_LITE_ORANGE|$06,  COLOR_LITE_ORANGE|$04, $02,$00
	.byte $0E,COLOR_ORANGE_GREEN|$0E, COLOR_ORANGE_GREEN|$0C, COLOR_ORANGE_GREEN|$0A, COLOR_ORANGE_GREEN|$08, COLOR_ORANGE_GREEN|$06, COLOR_ORANGE_GREEN|$04,$02,$00

BOOM_CYCLE_OFFSET ; Base offset (row * 9) to the color entries and P/M images for the cycle.
	.byte $00,9,18,27,36,45,54,63,72
	
BOOM_CYCLE_HPOS ; by cycle frame -- relative to Brick from BRICK_XPOS_LEFT_TABLE
	.byte $ff,$ff,$00,$00,$01,$02,$03,$04,$04

BOOM_CYCLE_SIZE ; by cycle frame
	.byte PM_SIZE_DOUBLE ; 6 bits * 2 color clocks == 12 color clocks. ; 1
	.byte PM_SIZE_DOUBLE ; 6 bits * 2 color clocks == 12 color clocks. ; 2
	.byte PM_SIZE_DOUBLE ; 5 bits * 2 color clocks == 10 color clocks. ; 3
	.byte PM_SIZE_DOUBLE ; 5 bits * 2 color clocks == 10 color clocks. ; 4
	.byte PM_SIZE_NORMAL ; 8 bits * 1 color clocks == 8 color clocks.  ; 5
	.byte PM_SIZE_NORMAL ; 6 bits * 1 color clocks == 6 color clocks.  ; 6
	.byte PM_SIZE_NORMAL ; 4 bits * 1 color clocks == 4 color clocks.  ; 7
	.byte PM_SIZE_NORMAL ; 2 bits * 1 color clocks == 2 color clocks.  ; 8
	.byte PM_SIZE_NORMAL ; 2 bits * 1 color clocks == 2 color clocks.  ; 9
	
BOOM_ANIMATION_FRAMES ; 7 bytes of Player image data per each cycle frame -- 8th and 9th byte 0 padded, since we are putting the * 9 offset table to dual use.  
	.byte $FC,$FC,$FC,$FC,$FC,$FC,$FC,$00,$00 ; 7 scan lines, 6 bits * 2 color clocks == 12 color clocks. ; 1
	.byte $FC,$FC,$FC,$FC,$FC,$FC,$FC,$00,$00 ; 7 scan lines, 6 bits * 2 color clocks == 12 color clocks. ; 2
	.byte $00,$F8,$F8,$F8,$F8,$F8,$00,$00,$00 ; 5 scan lines, 5 bits * 2 color clocks == 10 color clocks. ; 3
	.byte $00,$F8,$F8,$F8,$F8,$F8,$00,$00,$00 ; 5 scan lines, 5 bits * 2 color clocks == 10 color clocks. ; 4
	.byte $00,$00,$FF,$FF,$FF,$00,$00,$00,$00 ; 3 scan lines, 8 bits * 1 color clocks == 8 color clocks.  ; 5
	.byte $00,$00,$FC,$FC,$FC,$00,$00,$00,$00 ; 3 scan lines, 6 bits * 1 color clocks == 6 color clocks.  ; 6
	.byte $00,$00,$00,$F0,$00,$00,$00,$00,$00 ; 1 scan line, 4 bits * 1 color clocks == 4 color clocks.   ; 7
	.byte $00,$00,$00,$C0,$00,$00,$00,$00,$00 ; 1 scan line, 2 bits * 1 color clocks == 2 color clocks.   ; 8
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00 ; 0 scan line, 0 bits * 0 color clocks == 0 color clocks.   ; 9

	
	
	
	
	
	
	
	
	
	
	
	
	



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

	; Set initial display values to be certain everything begins 
	; at a known state with the title.

;	lda TITLE_HPOSP0    ; set horizontal position for Player as Title character
;	sta HPOSP0
	
;	lda #PM_SIZE_NORMAL ; set size for Player as Title character 
;	sta SIZEP0

	lda #4     ; Horizontal fine scrolling. 
	sta HSCROL ; Title textline is shifted by HSCROLL to center it.
	
	; Force the initial DLI just in case one goes crazy and the 
	; DLI chaining gets messed up. 
	; This may be commented out when code is more final.
	
	lda #<DISPLAY_LIST_INTERRUPT ; DLI Vector
	sta VDSLST
	lda #>DISPLAY_LIST_INTERRUPT
	sta VDSLST+1

	
; ==============================================================
; TITLE FLY IN
; ==============================================================

; End of Title section.
End_Title 

; whatever was decided for scrolling and flying text, 
; commit it to hardware for the title at the top of 
; the screen, so the first DLI does not have to do it.
	lda #0
;	lda TITLE_VSCROLL
	sta VSCROL
	
;	lda TITLE_HPOSP0
;	sta HPOSP0



	
	
; ==============================================================
; BALL:
; ==============================================================


End_Ball_Update	


;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

;	lda DIAG_SLOW_ME_CLOCK
;	beq ?Continue_Thumper
;	dec DIAG_SLOW_ME_CLOCK
;	jmp Exit_VBI

;?Continue_Thumper
;	lda #$0D
;	sta DIAG_SLOW_ME_CLOCK
	
	
	

	
Thumper_Animator_VBI
; X is the Thumper type:
; 0 = horizontal, 
; 1 = left, 
; 2 = right
;
; Y is the current animation frame (if an animation 
; is in progress.)


End_Thumper_Bumper_VBI	
	
	
	

	
; ==============================================================
; BRICKS
; ==============================================================
; "Bricks" refers to the playfield bricks and 
; the graphics for the Title log and the Game
; Over screen.  "Bricks" may also be an empty
; line to remove/transition these objects between
; the different displays.
;
; The Bricks may be in a static state for maintaining 
; current contents, or in a transition state 
; moving another screen contents on to the display.
;
; The MAIN code preps the BRICK lines for movement,
; sets the direction of each, and then notifies the 
; VBI to make the updates.
;
; The VBI cares not about the game mode.  It only 
; cares whether or not the bricks lines should be 
; in motion and what direction to move them.
;
; Motion speed is a tricky thing. When moving a new
; set of game playfield bricks they must be in place 
; before the ball can travel down from the bottom 
; border of the bricks, to the paddle and back up to 
; the bottom row of bricks. 

; At current specs: 
; bottom of bricks = line 133 + 1 line = 134 
; Paddle = scan line 205 - 1 line = 204
; That is a distance of 70 lines travelled twice,
; a total of 140 scan lines.

; Taking into account worse case motion rounding when
; the ball hits the paddle that's potentially three
; less scan lines, or an actual 137 lines traveled. 
; At its fastest, the ball travels 3 scan lines per
; frame.
; 137 scan lines / 3 lines per frame means the new
; playfield must be moved into place in 45 frames
; or less.

; The scroll width of a full screen is 168 color 
; clocks. (160 for visible screen plus one byte 
; of pixels additional for spacing between screens).
; 168 color clocks / 45 frames is 3.7 color clocks
; per frame. 
; Therefore, rounding up to 4 color clocks per frame,
; the screen can transition in 42 frames, leaving 
; a few frames for safety.  

; Note that only the lowest line of bricks must be 
; in place at this time, so the ball can hit the 
; row. The other higher lines can begin moving later, 
; or move slower lending a more fluid look to 
; the transition.
; 
; The Title Logo and the Game Over graphics can 
; transition at any speed possible, since the ball
; is not dependant (or even visible) when these 
; graphics are on screen.
; 
; Scrolling to the left screen needs a special case, 
; because the final stopping location is outside the 
; 0 - 7 color clock positions used for scrolling.
; (and using 0-15 would make this even more weird.)
; 
; Reminders: 
; Move view right/screen contents Left = Decrement HSCROL, Increment LMS
; Move view left/screen contents Right = Increment HSCROL, Decrement LMS.
;
; Two different screen moves here.  
;
; The first is an immediate move to the declared positions.  This would 
; be used to reset to starting positions before setting up a scroll.
;
; The second scroll is fine scroll from current position to target position.
;
	lda BRICK_SCREEN_IMMEDIATE_POSITION ; move screen directly.
	beq Fine_Scroll_Display             ; if not set, then try fine scroll
	
	ldx #7
Do_Next_Immediate_Move
	ldy BRICK_LMS_OFFSETS,x  ; Y = current position of LMS low byte in Display List
	lda BRICK_SCREEN_TARGET_LMS,x    ; Get destination position.
	sta BRICK_BASE,y                 ; Set the new Display List LMS pointer.
	lda BRICK_SCREEN_TARGET_HSCROL,x ; get the destination position.
	sta BRICK_CURRENT_HSCROL,x       ; set the current Hscrol for this row.
	
	dex
	bpl Do_Next_Immediate_Move

	lda #0  ; Clear the immediate move flag, and skip over doing fine scroll...
	sta BRICK_SCREEN_IMMEDIATE_POSITION
;	beq End_Brick_Scroll_Update
	jmp End_Brick_Scroll_Update

Fine_Scroll_Display   
	lda BRICK_SCREEN_START_SCROLL ; MAIN says to start scrolling?
	beq Check_Brick_Scroll        ; No?  So, is a Scroll already running.
	; and if a scroll is already in progress when MAIN toggles
	; the BRICK_SCREEN_START_SCROLL flag it really has no effect.
	; the current scroll keeps on scrolling.
	lda #0
	sta BRICK_SCREEN_START_SCROLL ; Turn off MAIN request.
	inc BRICK_SCREEN_IN_MOTION    ; Temporarily flag Scroll in progress.

Check_Brick_Scroll
	lda BRICK_SCREEN_IN_MOTION
	bne Set_Brick_In_Motion
;	beq End_Brick_Scroll_Update
	jmp End_Brick_Scroll_Update

Set_Brick_In_Motion
	lda #0     ; Temporarily indicate no motion
	sta BRICK_SCREEN_IN_MOTION 
	
	ldx #7 ; start at last/bottom row.
	
Check_Pause_or_Movement
	lda BRICK_SCREEN_MOVE_DELAY,x ; Delay for frame count?
	beq Move_Brick_Row
	inc BRICK_SCREEN_IN_MOTION ; indicate things in progress
	dec BRICK_SCREEN_MOVE_DELAY,x
	jmp Do_Next_Brick_Row
	
Move_Brick_Row
	ldy BRICK_LMS_OFFSETS,x ; Y = current position of LMS low byte in Display List
	lda BRICK_BASE,y                ; What is the Display List LMS pointer now?
	cmp BRICK_SCREEN_TARGET_LMS,x   ; Does it match target?
	beq Finish_Brick_HScroll        ; Yes.  Then is more HScroll needed?

	lda BRICK_SCREEN_DIRECTION,x 	; Are we going left or right?
	bpl Do_Bricks_Right_Scroll		; -1 = view Right/graphics left, +1 = view left/graphics right

; scroll View Right/screen contents left 
	lda BRICK_CURRENT_HSCROL,x      ; get the current Hscrol for this row.
	sec
	sbc BRICK_SCREEN_HSCROL_MOVE,X  ; decrement it to move graphics left.
	bpl Update_HScrol       ; If not negative, then no coarse scroll.

	clc                     ; Add to return this...
	adc #8                  ; ... to positive. (using 8, not 16 color clocks)
	pha
	lda BRICK_BASE,y        ; Increment LMS to Coarse scroll it
	adc #1
	sta BRICK_BASE,y
	pla
	bne Update_HScrol
	
Do_Bricks_Right_Scroll	    ; Move view left/screen contents Right
	lda BRICK_CURRENT_HSCROL,x      ; get the current Hscrol for this row.
	clc
	adc BRICK_SCREEN_HSCROL_MOVE,X  ; increment it to move graphics right.
	cmp #8 ; if greater or equal to 8
	bcc Update_HScrol       ; If no carry, then less than 8/limit.

	sec                     
	sbc #8                  ; Subtract 8 (using 8, not 16 color clocks)
	pha
	
	lda BRICK_BASE,y 
	sbc #1       ; Coarse scroll it
	; need special compensation to check for end position, because that 
	; is at byte 0, hscrol 8, not hscrol 0-7


	bpl Update_HScrol ; still positive, so we did not pass byte 0, hscrol 8
	lda #0            ; back it up to the end position...
	sta BRICK_BASE,y  ; byte 0
	lda #8            ; hscrol 8
	bpl Update_HScrol

; The current LMS matches the target LMS. 
; a final Hscroll may be needed.
Finish_Brick_HScroll 
	lda BRICK_CURRENT_HSCROL,X
	cmp BRICK_SCREEN_TARGET_HSCROL,x
	beq Do_Next_Brick_Row ; Everything matches. nothing to do.

	lda BRICK_SCREEN_DIRECTION,x 	; Are we going left or right?
	bpl Do_Finish_Right_Scroll		; -1 = view left/graphics right, +1 = view Right/graphics left
	
; scroll View Left/screen contents right 
	lda BRICK_CURRENT_HSCROL,x      ; get the current Hscrol for this row.
	sec
	sbc BRICK_SCREEN_HSCROL_MOVE,X  ; decrement it to move graphics left.
	bmi Set_Left_Home               ; If it went negative reset to end position.
	bpl Update_HScrol               ; If not negative, then no coarse scroll.
Set_Left_Home
	lda BRICK_SCREEN_TARGET_HSCROL,x ; if it went negative then reset to home
	sta BRICK_CURRENT_HSCROL,X
	jmp Update_HScrol
	
Do_Finish_Right_Scroll
	lda BRICK_CURRENT_HSCROL,x      ; get the current Hscrol for this row.
	clc
	adc BRICK_SCREEN_HSCROL_MOVE,X  ; increment it to move line right.
	cmp BRICK_SCREEN_TARGET_HSCROL,X ; if greater or equal to, then set to limit
	bcc Update_HScrol       ; If no carry, then did not exceed limit.
	lda BRICK_SCREEN_TARGET_HSCROL,X                     

Update_HScrol
	inc BRICK_SCREEN_IN_MOTION ; indicate things in motion
	sta BRICK_CURRENT_HSCROL,X ; Save new HSCROL.

Do_Next_Brick_Row
	dex
	bmi End_Brick_Scroll_Update
;	bpl Check_Pause_or_Movement ; Do_Row_Movement
	jmp Check_Pause_or_Movement
	
End_Brick_Scroll_Update


	
	
	
	
	
	

;===============================================================================
; THE END OF USER DEFERRED VBI ROUTINE 
;===============================================================================

Exit_VBI
; Finito.
	jmp XITVBV


	

	

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




DLI_1 ; Save registers
	pha


End_DLI_1 ; End of routine.  Point to next routine.
	lda #<DLI_2
	sta VDSLST
	lda #>DLI_2
	sta VDSLST+1
	
	pla ; Restore registers for exit

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

	
	
	

	
	
	
End_DLI_2 ; End of routine.  Point to next routine.
	lda #<DLI_3
	sta VDSLST
	lda #>DLI_3
	sta VDSLST+1

	pla
	tay
	pla
	tax
	pla

	rti


	
	
	
	
	
	
; DLI3: Hkernel 8 times....
;      Set HSCROLL for line, VSCROLL = 5, then Set COLPF0 for 5 lines.
;      Reset VScroll to 1 (allowing 2 blank lines.)
;      Set P/M Boom objects, HPOS, COLPM, SIZE
;      Repeat HKernel.
;
; Define 8 rows of Bricks.
; Each is 5 lines of mode C graphics, plus 2 blank line.
; The 5 rows of graphics are defined by using the VSCROL
; exploit to expand one line of mode C into five lines.
;
; This:
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
;   .byte DL_BLANK_2
; Becomes this:
;   DL_MAP_C
;   DL_MAP_C
;   DL_MAP_C
;   DL_MAP_C
;   DL_MAP_C
;   Blank Line
;   Blank Line
;
; The Blank lines provide space for expansion of the boom blocks over the bricks.
; Therefore they must be positioned in the blank line before the brick line.
; (An extra blank scan line follows the line starting the DLI to allow for this
; space on the first line)
;
; So, here is the DLI line change order:
;   DL_BLANK_1|DL_DLI                      Set hpos, size, color for Boom 1 and Boom2 (1)
;   DL_BLANK_1                             Set Vscroll 11 and HSCROLL for Brick Line 1 - set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set VScroll 0
;   DL_BLANK_1                             Set hpos, size, color for Boom 1 and Boom2 (2)
;   DL_BLANK_1                             Set Vscroll and HSCROLL for Brick Line 2 - set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set VScroll 0
;   DL_BLANK_1                             Set hpos, size, color for Boom 1 and Boom2 (3)
;   DL_BLANK_1                             Set Vscroll and HSCROLL for Brick Line 3 - set color COLPF0
; etc. . . .
;   DL_BLANK_1                             Set hpos, size, color for Boom 1 and Boom2 (8)
;   DL_BLANK_1                             Set Vscroll and HSCROLL for Brick Line 8 - set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set VScroll 0
;   DL_BLANK_1
;   DL_BLANK_1
;-------------------------------------------
; color 1 = bricks.
; Player 1 = Boom animation 1
; Player 2 = Boom animation 2
;-------------------------------------------
; per brick line
; COLPM1, COLPM2
; HPOSP1, HPOSP2
; SIZEP1, SIZEP2
; COLPF0, HSCROLL
;-------------------------------------------
DLI_3
	pha
	txa
	pha
	tya
	pha

	ldx #0  ; Starting at line 0 first line of bricks.

; DLI ENTRY IS AN EXTRA SCAN LINE ABOVE 
; WITH ONE BLANK LINE IN BETWEEN.

DLI3_DO_BOOM_AND_BRICKS

; Current position is 
; -2 == ENTRY line -- end of blank line AND
; 5 == LINE 1 of 2 BLANK for boom blocks which means we're at
; the ending line of a boom block for the prior brick row.

	; Set hscroll for the upcoming brick line.
	lda BRICK_CURRENT_HSCROL,x
	sta HSCROL
	
	; load up to set the next Boom animation postitions.
	lda BOOM_1_HPOS,x
	ldy BOOM_2_HPOS,x
	
	sta WSYNC ; drop to the top of the next boom block lines.

; -1 == 1 BLANK BEFORE 5 BLOCK
; 6 == LINE 2 of 2 BLANK

	; six store, four load after wsync.   Hope this fits. 
	; At least there's no graphics or character set DMA on this line.
	sta HPOSP1
	sty HPOSP2

	lda BOOM_1_SIZE,x
	sta SIZEP1
	lda BOOM_2_SIZE,x
	sta SIZEP2

	lda BOOM_1_COLPM,x
	sta COLPM1
	lda BOOM_2_COLPM,x
	sta COLPM2

	; Prep to apply color to the BRICK lines
	ldy BRICK_CURRENT_COLOR,x

	; Here we are triggering unnatural behavior in ANTIC.  Resetting
	; VSCROL to a value larger than the number of scan lines in this 
	; one-scan line graphics mode causes ANTIC to repeat the same line
	; of graphics data for several scan lines. This trick creates a 
	; 5 scan line tall brick that has the DMA LMS load of only one line. 
	; This allows convenient brick handling -- the main code only 
	; manipulates pixels for one graphics line line resulting in 
	; 5 lines of work. 

	; At the current position ANTIC is displying the second
	; blank line of a 2-blank line instruction (DL_BLANK_2 or $10)
	; VSCROL needs to be toggled to the number of scan lines in this 
	; instruction to stop ANTIC from adding more scan lines.
	
	lda #1 ; the blank instruction scan lines numbered 0, 1
	sta WSYNC
	
; 0 == LINE 1 of 5 BLOCK  (ANTIC MODE C, 1 scan line tall)

	sta VSCROL ; Reset to finish displaying the blank lines.
	; Next, trick Antic into extending the Mode C line.  
	; Setting 12 will display scan lines 12, 13, 14, 15, 0.
	lda #12  
	sta VSCROL

	sty COLPF0                ; scan line 12 (1)

	iny
	iny
	sty WSYNC
	
; 1 == LINE 2 of 5 BLOCK	
	
	sty COLPF0                ; scan line 13 (2)

	iny
	iny	
	sty WSYNC
	
; 2 == LINE 3 of 5 BLOCK	
		
	sty COLPF0                ; scan line 14 (3)

	iny
	iny
	sty WSYNC
	
; 3 == LINE 4 of 5 BLOCK	
	
	sty COLPF0                ; scan line 15 (4)

	iny
	iny
	sty WSYNC
	
; 4 == LINE 5 of 5 BLOCK	
	
	sty COLPF0                ; scan line 0 (5)

	; skip one blank scan line for the bottom edge of 
	; the current row of BOOM blocks.
	sta WSYNC    
		
; 5 == LINE 1 of 2 BLANK	

	inx                   ; next row of bricks
	cpx #8
	bne DLI3_DO_BOOM_AND_BRICKS

End_DLI_3 ; End of routine.  Point to next routine.
	lda #<DLI_4
	sta VDSLST
	lda #>DLI_4
	sta VDSLST+1


	lda #$0
	sta WSYNC
	sta COLBK
	
	
	pla
	tay
	pla
	tax
	pla

	rti


	
	
	
	
	
		
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

DLI_4
	pha

	lda #0
	ldy #$E0
	sty WSYNC
	sty CHBASE
	sta COLPF1
	lda #$0A
	sta COLPF2
	
	
;===============================================================================
; ****    **      ******  
; ** **   **        **   
; **  **  **        **   
; **  **  **        **   
; ** **   **        **   
; ****    ******  ******  
;===============================================================================

End_DLI_4 ; End of routine.  Point to next routine.
	lda #<DLI_1
	sta VDSLST
	lda #>DLI_1
	sta VDSLST+1

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

;DIAG_TEMP1 = PARAM_89 ; = $d0 ; DIAG_TEMP1

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

	sta DIAG1,y           ; write into screen RAM.
	
	lda DIAG_TEMP1        ; re-fetch the byte to display

	and #$0F              ; low nybble is second character
	tax
	lda ?NYBBLE_TO_HEX,x  ; simplify. no math.  just lookup table.

	iny
	sta DIAG1,y

	safeRTS ; restore regs for safe exit

?NYBBLE_TO_HEX ; hex binary values 0 - F in internal format
	.sbyte "0123456789ABCDEF"


	
	
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

;	lda #1
;	jsr MainSetTitle

;	lda #1
;	sta ENABLE_THUMPER


	jsr Set_VBI
	
	jsr WaitFrame 
	
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================
	
FOREVER
	
	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.
;	jsr WaitFrame ; Wait for VBI to run.




	
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

; Write selected byte values to diagnostic line on screen.

;	.sbyte " XT XL XR FT FL FR LT LL LR CT CL CR    "
	
;	mDebugByte THUMPER_PROXIMITY_TOP,      1 ; XT
	
;	mDebugByte THUMPER_PROXIMITY_LEFT,     4 ; XL

;	mDebugByte THUMPER_PROXIMITY_RIGHT,    7 ; XR
	
;	mDebugByte THUMPER_FRAME_TOP,         10 ; FT

;	mDebugByte THUMPER_FRAME_LEFT,        13 ; FL
	
;	mDebugByte THUMPER_FRAME_RIGHT,       16 ; FR
	
;	mDebugByte THUMPER_FRAME_LIMIT_TOP,   19 ; LT
	
;	mDebugByte THUMPER_FRAME_LIMIT_LEFT,  22 ; LL
	
;	mDebugByte THUMPER_FRAME_LIMIT_RIGHT, 25 ; LR
	
;	mDebugByte THUMPER_COLOR_TOP,         28 ; CT
	
;	mDebugByte THUMPER_COLOR_LEFT,        31 ; CL
	
;	mDebugByte THUMPER_COLOR_RIGHT,       34 ; CR
	
;	mDebugByte TITLE_COLOR_COUNTER,  37 ; CC

;	mDebugByte TITLE_DLI_PMCOLOR,    34 ; DP
;===============================================================================	
;	mDebugByte TITLE_SLOW_ME_CLOCK,  37 ; SM
;===============================================================================

	jmp FOREVER ; And again.  (and again) 




.local
;===============================================================================
;   Basic setup. Stop sound. Create screen.
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
;   Basic setup. Stop sound. Create screen.
;===============================================================================

Setup
; Make sure 6502 decimal mode is not set -- not  necessary, 
; but it makes me feel better to know this is not on.
	cld

	lda #0     ; Off. No DMA for display list, display, Player/Missiles.
	sta SDMCTL ; Display DMA control 
	
;	sta TITLE_HPOSP0 ; Zero horizontal position for Player used as Title character

	; Be clean and tidy.  Move P/M off screen.

	ldx #7
?Zero_PM_HPOS        ; 0 to 7, Zero horizontal position registers for P0-3, M0-3.
	sta HPOSP0,x
	dex
	bpl ?Zero_PM_HPOS

	; Be clean and tidy II. Set normal sizes.

	lda #PM_SIZE_NORMAL ; Reset size for Players

	ldx #3
?Normal_PM_Size
	sta SIZEP0,x
	dex
	bpl ?Normal_PM_Size
	
	lda #~01010101 ; 01, normal size for each missile.
	sta SIZEM
	
	sta GPRIOR       ; Zero GTIA Priority

	sta GRACTL       ; Turn off GTIA P/M data graphics control 

	lda #NMI_VBI     ; Turn OFF DLI leaving only VBI on.
	sta NMIEN
	
;===============================================================================
	jsr WaitFrame ; Wait for vertical blank updates from the shadow registers.
;===============================================================================

	; Set shadow register/defaults for the top of the screen.
	
	lda #<DISPLAY_LIST ; Set Display List address
	sta SDLSTL
	lda #>DISPLAY_LIST
	sta SDLSTH
	
	lda #<DISPLAY_LIST_INTERRUPT ; Set the DLI Vector
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
	
	lda #>PLAYER_MISSILE_BASE ; Set Player/Missile graphics memory base address.
	sta PMBASE
	;
	; Set Missiles = 5th Player (COLPF3)
	; Set Priority with Players/Missiles on top
	;
	lda #[FIFTH_PLAYER|1]  
	sta GPRIOR

	lda #[ENABLE_PLAYERS|ENABLE_MISSILES]
	sta GRACTL ; Turn on GTIA P/M data graphics Control 

	lda #[NMI_DLI|NMI_VBI] ; Turn ON DLI and VBI Interrupt flags 
	sta NMIEN
	
	lda #>CHARACTER_SET_01 ; Character set for title
	sta CHBAS
	;
	; Draw vertical Thumpers
	;
	ldx #MIN_PIXEL_Y
	lda #$80
?Init_Vertical_Thumpers
	sta PMADR_BASE3,x
	sta PMADR_MISSILE,x
	inx
	cpx #MAX_PIXEL_Y
	bne ?Init_Vertical_Thumpers

 
	rts 
 

.local
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

;	sta TITLE_STOP_GO
	
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

