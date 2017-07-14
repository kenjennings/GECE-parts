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
;
; The Atari OS has defined purpose for the first half of Page Zero 
; locations.  Since no Floating Point will be used here we'll 
; borrow everything in the second half of Page Zero.
;
;===============================================================================
;
; This list is a disorganized, royal mess.  Next time don't start 
; with the page zero list allowed for BASIC.  Just start at $80 and 
; run straight until $FF.
;
; Zero Page fun.  This is assembly, dude.  No BASIC in sight anywhere.
; No BASIC means we can get craaaazy with the second half of Page Zero.
;
; In fact, there's no need to have the regular game variables out in high memory.  
; All the Byte-sized values are hereby moved to Page 0.
;
;===============================================================================

PARAM_00 = $D4 ; ZMR_ROBOTO  -- Is Mr Roboto playing the automatic demo mode? init 1/yes
PARAM_01 = $D6 ; ZDIR_X      -- +1 Right, -1 Left.  Indicates direction of travel.
PARAM_02 = $D7 ; ZDIR_Y      -- +1 Down, -1 Up.  Indicates direction of travel.

PARAM_06 = $DC ; V_TEMP_ROW   -- VBI: Temporary Boom Block Row
PARAM_07 = $DD ; V_TEMP_CYCLE -- VBI: Temporary Boom Block Cycle

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

PARAM_83 = $ca ; ZCOLLISION  -- Is Brick present at tested location? 0 = no, 1 = yes
PARAM_84 = $cb ; ZBRICK_LINE -- coord_Y reduced to line 1-8
PARAM_85 = $cc ; ZBRICK_COL  -- coord_X reduced to brick number 1-14
PARAM_86 = $cd ; ZCOORD_Y    -- coord_Y for collision check
PARAM_87 = $ce ; ZCOORD_X    -- coord_X for collision check 
PARAM_88 = $cf ; V_15FPS_TICKER -- When this is 0, then 1/4 tick events occur.
PARAM_89 = $d0 ; M_TEMP1  -- local temporary value
PARAM_90 = $d1 ; DIAG_BRICK_Y - remember Y for looping brick destruction 
PARAM_91 = $d2 ; DIAG_BRICK_X - remember X for looping brick destruction
PARAM_92 = $d3 ; DIAG_SLOW_ME_CLOCK
PARAM_93 = $d5 ; DIAG_TEMP1

PARAM_94 = $D8 ; MAIN: Direction Index
PARAM_95 = $D9 ; MAIN: Speed Index
PARAM_96 = $DA ; MAIN: Delay Index
PARAM_97 = $DB ; MAIN: Temporary SAVE/PHA


PARAM_98 = $DE ; V_20FPS_TICKER -- When this is 0, then 1/3 tick events occur.
PARAM_99 = $DF ; V_30FPS_TICKER -- When this is 0, then 1/2 tick events occur

ZEROPAGE_POINTER_2 = $E0 ;
ZEROPAGE_POINTER_3 = $E2 ; 
ZEROPAGE_POINTER_4 = $E4 ; 
ZEROPAGE_POINTER_5 = $E6 ;
ZEROPAGE_POINTER_6 = $E8 ;
ZEROPAGE_POINTER_7 = $EA ; ZTEMP_PMADR   -- VBI uses for boom block image target 
ZEROPAGE_POINTER_8 = $EC ; ZBRICK_BASE   -- Pointer to start of bricks on a line.
ZEROPAGE_POINTER_9 = $EE ; ZTITLE_COLPM0 -- VBI sets for DLI to use



;===============================================================================
;   DECLARE VALUES AND ADDRESS ASSIGNMENTS (NOT ALLOCATING MEMORY)
;===============================================================================

ZMR_ROBOTO =  PARAM_00 ; Is Mr Roboto playing the automatic demo mode? init 1/yes

ZDIR_X =      PARAM_01 ; +1 Right, -1 Left.  Indicates direction of travel.
 
ZDIR_Y =      PARAM_02 ; +1 Down, -1 Up.  Indicates direction of travel.


ZCOLLISION =  PARAM_83 ; Is Brick present at tested location? 0 = no, 1 = yes

ZBRICK_LINE = PARAM_84 ; Ycoord reduced to line 1-8

ZBRICK_COL =  PARAM_85 ; Xcoord reduced to brick number 1-14

ZCOORD_Y =    PARAM_86 ; Ycoord for collision check

ZCOORD_XP =   PARAM_87 ; Xcoord for collision check  


V_15FPS_TICKER = PARAM_88 ; count 0, 1, 2, 3, 0, 1, 2, 3... 0 triggers animation events.

V_20FPS_TICKER = PARAM_98 ; count 0, 1, 2, 0, 1, 2... 0 triggers animation events.

V_30FPS_TICKER = PARAM_99 ; count 0, 1, 0, 1... 0 triggers animation events.

; flag when timer counted (29 sec). Used on the
; title and game over  and auto play screens. When auto_wait
; ticks it triggers automatic transition to the 
; next screen.
ZAUTO_NEXT =    PARAM_76 ; .byte 0

ZBRICK_COUNT =  PARAM_77 ; .byte 112 (full screen of bricks, 8 * 14)

ZBRICK_POINTS = PARAM_78 ; .byte $00

ZBALL_COUNT =   PARAM_79 ; .byte $05


ZTEMP_PMADR =   ZEROPAGE_POINTER_7 ; $EA - VBI uses for boom block image target 

ZBRICK_BASE =   ZEROPAGE_POINTER_8 ; $EC - Pointer to start of bricks on a line.

ZTITLE_COLPM0 = ZEROPAGE_POINTER_9 ; $EE - VBI sets for DLI to use


V_TEMP_ROW =   PARAM_06 ; = $DC ; -- VBI: Temporary Boom Block Row
V_TEMP_CYCLE = PARAM_07 ; = $DD ; -- VBI: Temporary Boom Block Cycle


M_DIRECTION_INDEX = PARAM_94 ; = $D8 ; MAIN: Direction Index
M_SPEED_INDEX =     PARAM_95 ; = $D9 ; MAIN: Speed Index
M_DELAY_INDEX =     PARAM_96 ; = $DA ; MAIN: Delay Index
M_TEMP_PHA =        PARAM_97 ; = $DB ; MAIN: Temporary SAVE/PHA

M_TEMP1 = PARAM_89 ; = $d0 ;   -- local temporary value




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


;==============================================================
; THUMPER-BUMPER.
;==============================================================
; Proximity set by MAIN code:
; 
THUMPER_PROXIMITY =       PARAM_23
THUMPER_PROXIMITY_TOP =   PARAM_23 ;	.byte $09 
THUMPER_PROXIMITY_LEFT =  PARAM_24 ;	.byte $09 
THUMPER_PROXIMITY_RIGHT = PARAM_25 ;	.byte $09 
;
; VBI maintains animation frame progress
;
THUMPER_FRAME =       PARAM_26
THUMPER_FRAME_TOP =   PARAM_26 ;	.byte 0 ; 0 is no animation. VBI Sets DLI vector for this.
THUMPER_FRAME_LEFT =  PARAM_27 ;	.byte 0 ; 0 is no animation. DLI sets HPOS and SIZE
THUMPER_FRAME_RIGHT = PARAM_28 ;	.byte 0 ; 0 is no animation. DLI sets HPOS and SIZE
;
; VBI maintains animation frames  (these were originally different)
;
THUMPER_FRAME_LIMIT =       PARAM_29
THUMPER_FRAME_LIMIT_TOP =   PARAM_29 ;	.byte 12 ; at 12 return to 0
THUMPER_FRAME_LIMIT_LEFT =  PARAM_30 ;	.byte 12  ; at 12 return to 0
THUMPER_FRAME_LIMIT_RIGHT = PARAM_31 ;	.byte 12  ; at 12 return to 0
;
; VBI sets colors, and DLI2 sets them on screen.
;
THUMPER_COLOR =       PARAM_32
THUMPER_COLOR_TOP =   PARAM_32 ;	.byte 0
THUMPER_COLOR_LEFT =  PARAM_33 ;	.byte 0
THUMPER_COLOR_RIGHT = PARAM_34 ;	.byte 0

ENABLE_THUMPER = PARAM_82 ; should have thought of this earlier.



;==============================================================
; BALL:
;==============================================================
; Very simple.  
; MAIN code analyzes CURRENT position of the ball to set the NEW postion.
; VBI code updates the Player image and sets NEW as CURRENT.
; Everything else -- collisions and reactions are established by the MAIN code.

ENABLE_BALL = PARAM_39
; .byte 0 ; set by MAIN to turn on and off the ball.

BALL_CURRENT_X = PARAM_40
; .byte 0
BALL_CURRENT_Y = PARAM_41
; .byte 0

BALL_HPOS = PARAM_42
; .byte 0 ; this lets VBI tell DLI to remove from screen without zeroing CURRENT

BALL_NEW_X = PARAM_43
; .byte 0 ; DLI sets HPOSP0
BALL_NEW_Y = PARAM_44
; .byte 0 ; VBI moves image

BALL_COLOR = PARAM_45
; .byte $0E ; and color.  always bright.



;===============================================================================
; ****   ******   **    *****   ****
; ** **    **    ****  **      **  **
; **  **   **   **  ** **      ** ***
; **  **   **   **  ** ** ***  *** **
; ** **    **   ****** **  **  **  **
; ****   ****** **  **  *****   ****
;===============================================================================

DIAG_TEMP1 = PARAM_89 ; = $d0 ; DIAG_TEMP1

DIAG_SLOW_ME_CLOCK = PARAM_88 ; = $cf ; DIAG_SLOW_ME_CLOCK



;===============================================================================
;   INITIALIZE ZERO PAGE VALUES
;===============================================================================

	*= THUMPER_PROXIMITY
	.byte $7f,$7f,$7f  ; value will not trigger proximity animation
;
; VBI maintains animation frame progress
;
	*= THUMPER_FRAME
	.byte 0,0,0 ; 0 is no animation. VBI Sets DLI vector for this.

	*= THUMPER_FRAME_LIMIT  
	.byte 6,6,6 ; at this limit return animation frame to 0 

	*= THUMPER_COLOR
	.byte $02,$02,$02
;
; BALL values
;
	*= ENABLE_BALL 
	.byte 0,$80,$80,$80,$80,$80,$0E
; ENABLE_BALL    .byte 0  set by MAIN to turn on and off the ball.
; BALL_CURRENT_X .byte 0
; BALL_CURRENT_Y .byte 0
; BALL_HPOS      .byte 0  this lets VBI tell DLI to remove from screen without zeroing CURRENT
; BALL_NEW_X     .byte 0  DLI sets HPOSP0
; BALL_NEW_Y     .byte 0  VBI moves image
; BALL_COLOR     .byte $0E   and color.  always bright.




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
PMADR_MISSILE = [PLAYER_MISSILE_BASE+$300] ; Ball.                            Ball counter.
PMADR_BASE0 =   [PLAYER_MISSILE_BASE+$400] ; Flying text. Boom brick. Paddle. Ball Counter.
PMADR_BASE1 =   [PLAYER_MISSILE_BASE+$500] ;              Boom Brick. Paddle. Ball Counter.
PMADR_BASE2 =   [PLAYER_MISSILE_BASE+$600] ; Thumper.                 Paddle. Ball Counter.
PMADR_BASE3 =   [PLAYER_MISSILE_BASE+$700] ; Thumper.                 Paddle. Ball Counter.

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




; ( *= $8F00 to $8F3F )
; Master copies (source copied to working screen)
;
EMPTY_LINE ; 64 bytes of 0.
	.dc $0040 $00 ; 64 bytes of 0.                  Relative +$0300


	

; ( *= $8F40 to $8F53 ) 20 bytes
; Horizontal thumper lines is same width as bricks, but it 
; has no gaps.
;
THUMPER_LINE
	.byte ~00011111, ~11111111, ~11111111, ~11111111, ~11111111 
	.byte ~11111111, ~11111111, ~11111111, ~11111111, ~11111111 
	.byte ~11111111, ~11111111, ~11111111, ~11111111, ~11111111 
	.byte ~11111111, ~11111111, ~11111111, ~11111111, ~11110000 


	
	
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



; I want the Display List Subroutines to start aligned 
; to a page for the same reason -- This gives them all 
; the same address high byte, so only the low byte
; of the address needs to be changed on JMP instructions
; to target a different subroutine.
	*=[*&$FF00]+$0100
	

	
; ( *= $92xx to ????????$92xx )  ( 43 bytes ) 
; Bumper Frames for animating horizontal bumper at top of screen
;
; Scan lines 42-52,  screen line 35-45,     11 various blank and graphics lines in routine

; idle state waiting for impact.  Line is visible when ball gets near.
THUMPER_FRAME_WAIT 
	.byte DL_BLANK_8      ;    8 lines
	.byte DL_BLANK_2      ; +  2 lines
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	;                    ==== 11 lines
	; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_THUMPER_RTS

THUMPER_FRAME0
	.byte DL_BLANK_8 ;    8 lines
	.byte DL_BLANK_3 ; +  3 lines 
	;               ==== 11 lines
	; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_THUMPER_RTS

THUMPER_FRAME1
	.byte DL_BLANK_5      ;    5 lines
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	;                    ==== 11 lines
	; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_THUMPER_RTS

THUMPER_FRAME2
	.byte DL_BLANK_6      ;    6 lines
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_BLANK_2      ;    2 lines
	;                    ==== 11 lines
	; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_THUMPER_RTS

THUMPER_FRAME3
	.byte DL_BLANK_5      ;    5 lines
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_BLANK_4      ;    4 lines
	;                    ==== 11 lines
	; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_THUMPER_RTS

THUMPER_FRAME4
	.byte DL_BLANK_4      ;    4 lines
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_BLANK_6      ;    6 lines
	;                    ==== 11 lines
	; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_THUMPER_RTS

THUMPER_FRAME5
	.byte DL_MAP_C|DL_LMS ; +  1 lines
	.word THUMPER_LINE
	.byte DL_BLANK_5      ;    5 lines
	.byte DL_BLANK_5      ;    5 lines
	;                    ==== 11 lines
	; Return to main display list
	.byte DL_JUMP
	.word DISPLAY_LIST_THUMPER_RTS





	

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
; Player 2 = Right Bumper
;-------------------------------------------
; COLPF0, COLPM3, COLPM2
; HPOSP3, HPOSP2
; SIZEP3, SIZEP2
;-------------------------------------------

	; Scan line 42,      screen line 35,         One blank scan lines

; Jump to Horizontal Thumper bumper

	; Scan lines 43-53,  screen line 36-46,     11 various blank and graphics lines in routine

; Jump back to Main list.

;-------------------------------------------
; PLAYFIELD SECTION: NORMAL
; color 1 = bricks
; Missile 3 (5th Player) = BALL 
; Player 0 = boom-o-matic animation 1
; Player 1 = boom-o-matic animation 1
;-------------------------------------------
;    and already set earlier:
; Player 3 = Left bumper 
; Player 2 = Right Bumper
;-------------------------------------------
; COLPF0, COLPM0, COLPM1, COLPF3
; HPOSP0, HPOSP1, HPOSM3
; SIZEP0, SIZEP1, SIZEM3
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
; Missile 3 (5th Player) = Ball
; Player 3 = Left bumper 
; Player 2 = Right Bumper
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
; Missile 3 (5th Player) = BALL
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
; Missile 3 == Sine Wave Balls
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
; Alignment to the next 256 byte Page is sufficient insurance 
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

	
	.byte DL_JUMP	        ; Jump to horizontal thumper animation frame
DISPLAY_LIST_THUMPER_VECTOR ; remember this -- update low byte to change frames
	.word THUMPER_FRAME_WAIT
	
	; Note DLI started before thumper-bumper Display Lists for 
	; P/M HPOS, COLPM, SIZE and HITCLR
	; Also, this DLI ends by setting HPOS and COLPM for the BOOM 
	; objects in the top row of bricks. 

DISPLAY_LIST_THUMPER_RTS ; destination for animation routine return.
	; Top of Playfield is empty above the bricks. 
	; Scan line 54-77,   screen line 47-70,     24 blank lines

	

;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

; some blank lines, two lines diagnostics, a few more blank lines.

	.byte $70,$70,$70,$70
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



;===============================================================================
; THUMPER-BUMPER Proximity Force Field: 
;===============================================================================
; As the ball nears the top, left and right borders
; a force field begin charging.  When the ball reaches the 
; force field line the ball rebounds in conjunction 
; with a reactive bounce animation of the force field.
;
; Only values 9 to 0 are meaningful. 
; Value 0 triggers thumper anim.
; Proximity values >0 will not be respected
; when a thumper animation is in progress.
; Only value 0 will trigger the start of a 
; new thumper animation cycle.
;
; MAIN code sets the new proximity.  
; Proximity is Ball position - border postition 
;
; VBI reacts to new proximity.
; if animation is in progress then
;     update animation.
;     if proximity = 0 then (re)start animation.
; Else
;     if proximity >8 then no proxmity color.
;     if proximity 1 to 8 then set proximity color.
;	  if proximity = 0 then start animation.
; End if

; Display List-- Horizontal Thumper sequence
; The list is the low byte of the address of different
; versions of the bumper shape.  The VBI will overwite 
; the low byte of a JMP instruction in the Display
; List to point to the next frame in the animation.
;
;-------------------------------------------
; color 1 = horizontal/top bumper.
; Player 3 = Left bumper 
; Player 2 = Right Bumper
;-------------------------------------------
; COLPF0, 
; COLPM3, COLPM2
; HPOSP3, HPOSP2
; SIZEP3, SIZEP2
;-------------------------------------------

THUMPER_HORIZ_ANIM_TABLE
	.byte <THUMPER_FRAME_WAIT
	.byte <THUMPER_FRAME1
	.byte <THUMPER_FRAME2
	.byte <THUMPER_FRAME3
	.byte <THUMPER_FRAME4
	.byte <THUMPER_FRAME5

; Player 3 -- LEFT Vertical Thumper sequence
; Lists establish HPOS for DLI2.
; entry 0 is waiting state.
;
THUMPER_LEFT_HPOS_TABLE
	.byte MIN_PIXEL_X-1 ; Waiting for Proximity 
	.byte MIN_PIXEL_X-4
	.byte MIN_PIXEL_X-5
	.byte MIN_PIXEL_X-5
	.byte MIN_PIXEL_X-6
	.byte MIN_PIXEL_X-7

; Player 2 -- RIGHT Vertical Thumper sequence
; Lists establish HPOS for DLI2.
; entry 0 is waiting state.
;
THUMPER_RIGHT_HPOS_TABLE
	.byte MAX_PIXEL_X+1 ; Waiting for Proximity 
	.byte MAX_PIXEL_X+1
	.byte MAX_PIXEL_X+4
	.byte MAX_PIXEL_X+5
	.byte MAX_PIXEL_X+6
	.byte MAX_PIXEL_X+7

; Player size for both animations.
;
THUMPER_SIZE_TABLE
	.byte ~00000000 ; Waiting for Proximity 
	.byte ~00000011 
	.byte ~00000001
	.byte ~00000000
	.byte ~00000000
	.byte ~00000000
	
;
; THUMPER-BUMPER Proximity set by MAIN code:
; 
;THUMPER_PROXIMITY = PARAM_23
;THUMPER_PROXIMITY_TOP = PARAM_23   ;	.byte $80
;THUMPER_PROXIMITY_LEFT = PARAM_24  ;	.byte $80
;THUMPER_PROXIMITY_RIGHT = PARAM_25 ;	.byte $80
;
; VBI maintains animation frame progress
;
;THUMPER_FRAME = PARAM_26
;THUMPER_FRAME_TOP = PARAM_26   ;	.byte 0 ; 0 is no animation. VBI Sets DLI vector for this.
;THUMPER_FRAME_LEFT = PARAM_27  ;	.byte 0 ; 0 is no animation. DLI sets HPOS and SIZE
;THUMPER_FRAME_RIGHT = PARAM_28 ;	.byte 0 ; 0 is no animation. DLI sets HPOS and SIZE
;
; VBI maintains animation frames
;
;THUMPER_FRAME_LIMIT = PARAM_29
;THUMPER_FRAME_LIMIT_TOP = PARAM_29   ;	.byte 12 ; at 12 return to 0
;THUMPER_FRAME_LIMIT_LEFT = PARAM_30  ;	.byte 6  ; at 6 return to 0
;THUMPER_FRAME_LIMIT_RIGHT = PARAM_31 ;	.byte 6  ; at 6 return to 0
;
; VBI sets colors, and DLI2 sets them on screen.
;
;THUMPER_COLOR = PARAM_32
;THUMPER_COLOR_TOP = PARAM_32   ;	.byte 0
;THUMPER_COLOR_LEFT = PARAM_33  ;	.byte 0
;THUMPER_COLOR_RIGHT = PARAM_34 ;	.byte 0

; VBI sets the color of the thumper based on 
; the distance of the ball determined by the MAIN
; routine.
; (These colors are set when a thumper anim is NOT in progress).
; Therefore, adjusted distance 1 to 8 have a color.
; Distance 9 is black.  (maybe we'll make it very grey)
; Thumper animation (distance 0 ) is white.
; greater than 15 is color $02
THUMPER_PROXIMITY_COLOR
	.byte $9E,$8E,$7E,$6C,$5C,$4A,$98,$96,$96,$94,$94,$92,$92,$90,$90,$04,$02






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
; MAINTAIN SUB-60 FPS TICKERS
; ==============================================================
	;
	; 30 FPS...  tick off 0, 1, 0, 1, 0, 1...
	;
	inc V_30FPS_TICKER
	lda V_30FPS_TICKER
	and #~00000001
	sta V_30FPS_TICKER
	;
	; 20 FPS... tick 2, 1, 0, 2, 1, 0... a bit differently  
	;
	lda V_20FPS_TICKER
	bne Skip_20FPS_Reset
	lda #~00000100 ; #4  which becomes 2 in this iteration, then 1, then 0
Skip_20FPS_Reset
	lsr A 
	sta V_20FPS_TICKER
	;
	; 15 FPS... tick off 0, 1, 2, 3, 0, 1, 2, 3...
	;
	inc V_15FPS_TICKER
	lda V_15FPS_TICKER
	and #~00000011
	sta V_15FPS_TICKER
	
	
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

; Erase old image
	lda #0
	ldy BALL_CURRENT_Y
;	
	sta PMADR_MISSILE,y
	iny
	sta PMADR_MISSILE,y
	
	
	lda #$C0 ; The Ball
	ldy BALL_NEW_Y
	sty BALL_CURRENT_Y
	
	sta PMADR_MISSILE,y
	iny
	sta PMADR_MISSILE,y
	
; 
; and set the next current position.
	lda BALL_NEW_X
	sta BALL_CURRENT_X
	sta BALL_HPOS ; And let the DLI know where to put it.
;
; and unicorn colorfy it.
	lda RANDOM ; random color 
	ora #$0F   ; sparkle-white the luminance
	sta BALL_COLOR

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
	
	
	
; ==============================================================
; THUMPER-BUMPER PROXIMITY FORCE FIELD:
; ==============================================================
; First, evaluate changes the MAIN routine requests.
; If ball proximity reches 0 begin (or force restart 
; of) the thumper animation.
; If the animation is in progress, do not observe 
; the proximity state/color change.
; If no animation is in progress, then update THUMPER
; color per the ball proximity.

	lda ENABLE_THUMPER
	bne Thumper_Animator_VBI
;
; 0 == Turn off animations.
; Reset top no animation.
; Reset colors to 0.
;
	lda #0
	sta THUMPER_FRAME_TOP
	sta THUMPER_FRAME_LEFT
	sta THUMPER_FRAME_RIGHT
	
	sta THUMPER_COLOR_TOP
	sta THUMPER_COLOR_LEFT
	sta THUMPER_COLOR_RIGHT
	
	jmp End_Thumper_Bumper_VBI
	
Thumper_Animator_VBI
; X is the Thumper type:
; 0 = horizontal, 
; 1 = left, 
; 2 = right
;
; Y is the current animation frame (if an animation 
; is in progress.)

	ldx #0 ; Thumper type 0 = horizontal, 1 = left, 2 = right

; Allow first proximity frame to be set at any time, 
; but further animation occurs on the 20FPS clock.
	
Loop_Next_Thumper	
	lda THUMPER_PROXIMITY,X     ; X lets us loop for Top, Left, and Right
	bne Check_Thumper_Anim      ; Proximity not 0, check if anim is in progress.
	; Proximity is 0, (force) (re)start of animation
	lda THUMPER_PROXIMITY_COLOR ; First entry is animation color
	sta THUMPER_COLOR,x         ; set the bumper color
	                            ; !AUDIO! should engage here
	ldy #1                      ; 1 is first starting animation frame.
	bne Update_Thumper_Frame
	
Check_Thumper_Anim 	
	ldy THUMPER_FRAME,x         ; Is Anim in progress? 
	bne Thumper_Frame_Inc       ; Yes. no proximity color change.
	                            ; No animation running.
	cmp #16                     ; Is proximity 0 to 15?
	bcs Next_Thumper_Bumper     ; No. Too far away. No change.
	                              ; Proximity! Force field reaction! 
	tay                           ; Turn proximity into ...
	lda THUMPER_PROXIMITY_COLOR,y ; ... color table lookup.
	sta THUMPER_COLOR,x           ; set new color for DLI
	jmp Next_Thumper_Bumper

Thumper_Frame_Inc
	lda V_15FPS_TICKER          ; If the 20FPS clock has not ticked to 0...
	bne Next_Thumper_Bumper     ; then do not advance frame. Skip to next bumper check.
	
	ldy THUMPER_FRAME,x         ; Get current Frame
	beq Next_Thumper_Bumper     ; 0. No animation. Done.
	iny                         ; next frame.
	tya
	cmp THUMPER_FRAME_LIMIT,x   ; Reached the frame limit?
	bne Update_Thumper_Frame    ; No. Update frame.
	ldy [THUMPER_PROXIMITY_COLOR+16] ; Yes. Reset the proximity 
	sty THUMPER_COLOR,x         ;  color to "waiting"
	ldy #0                      ; Return to frame 0.
Update_Thumper_Frame            
	sty THUMPER_FRAME,x         ; Save frame counter;
	; The DLI will handle the color of all bumpers, and the 
	; Player/Missile placement of the left and right bumpers.
	; But, bumper type 0 (top/horizontal bumper) is different.
	; This bumper is done by changing the Display list. 
	; Rather not have MAIN do this and possibly miss the 
	; timing to update the address for the frame.
	; Here VBI updates the Display List routine vector.
	cpx #0 
	bne Next_Thumper_Bumper         ; For bumper 1 and 2 we're done.
	lda THUMPER_HORIZ_ANIM_TABLE,y  ; Get low byte of animation display list subroutine
	sta DISPLAY_LIST_THUMPER_VECTOR ; put it in the JMP target address.

Next_Thumper_Bumper
	inx                         ; next Thumper to animate
	cpx #3                      ; Reached the last thumper.
	bne Loop_Next_Thumper       ; Go do the next one.

End_Thumper_Bumper_VBI	
	
	
	
	

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

	; GTIA Fifth Player/Missiles = COLPF3. Priority 2 = PM0/1, Playfield, PM2/3
	lda #[FIFTH_PLAYER|2] 
	sta PRIOR
	sta HITCLR ; in case we use P/M collision detection in the playfield.

	; Screen parameters... 
	; need full width screen for thumper/brick sections.
	;
	lda #[ENABLE_DL_DMA|ENABLE_PM_DMA|PLAYFIELD_WIDTH_NORMAL|PM_1LINE_RESOLUTION]
	STA WSYNC
	sta DMACTL

	; Top thumper-bumper.  Only set color.  The rest of the animation is
	; done in the Display list and set by the VBI.
	lda THUMPER_COLOR_TOP
	sta COLPF0

	; Left thumper-bumper -- Player 3. P/M color, position, and size.
	lda THUMPER_COLOR_LEFT
	sta COLPM3

	ldy THUMPER_FRAME_LEFT        ; Get animation frame
	lda THUMPER_LEFT_HPOS_TABLE,y ; P/M position
	sta HPOSP3
	lda THUMPER_SIZE_TABLE,y ; P/M size
	sta SIZEP3

	; Right thumper-bumper -- Player 2.  Set P/M color, position, and size.
	lda THUMPER_COLOR_RIGHT
	sta COLPM2 

	ldy THUMPER_FRAME_RIGHT        ; Get animation frame
	lda THUMPER_RIGHT_HPOS_TABLE,y ; P/M position
	sta HPOSP2
	lda THUMPER_SIZE_TABLE,y ; P/M size
	sta SIZEP2


	; Establish the ball. Missile 3.
	
	lda BALL_COLOR
	sta COLPF3
	
	lda BALL_HPOS
	sta HPOSM3
	
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


		
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

DLI_3
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

End_DLI_3 ; End of routine.  Point to next routine.
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

	lda #1
	sta ENABLE_THUMPER


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


; Minimal Ball stuff.

; Horizontal
; BALL_MOVE_X	
	ldx BALL_CURRENT_X
	lda ZDIR_X
	bmi BALL_GO_LEFT
; Then, BALL_GO_RIGHT
	inx
	cpx #MAX_PIXEL_X ; Not MAX_BALL_X, because this ball is 1 color clocks wide
	bne BALL_END_X
; Then, reached right limit
	lda #$FF ; now going left
	bmi BALL_END_X
BALL_GO_LEFT
	dex
	cpx #MIN_BALL_X
	bne BALL_END_X
; Then reached left limit
	lda #1
BALL_END_X
	stx BALL_NEW_X
	sta ZDIR_X
	
; Vertical
; BALL_MOVE_Y
	ldx BALL_CURRENT_Y
	lda ZDIR_Y
	bmi BALL_GO_UP
; Then, BALL_GO_DOWN
	inx
	cpx #MAX_PIXEL_Y
	bne BALL_END_Y
; Then, reached bottom limit
	lda #$FF ; now going up
	bmi BALL_END_Y
BALL_GO_UP
	dex
	cpx #MIN_PIXEL_Y
	bne BALL_END_Y
; Then reached left limit
	lda #1
BALL_END_Y
	stx BALL_NEW_Y
	sta ZDIR_Y

; Clear proximity in case direction changed
	lda #$80
	sta THUMPER_PROXIMITY_TOP
	sta THUMPER_PROXIMITY_LEFT
	sta THUMPER_PROXIMITY_RIGHT

; Note that this will not work for the actual game when the 
; ball may move up to 3 pixels or scan lines in a 
; frame.  In this case, 0 proximity will need to be 
; remembered when the ball hit the edge, but the remaining
; ball movements must still be calculated.

; Calculate proximity top only when moving up
	lda ZDIR_Y
	bpl ?Calculate_Proximity_Left; Moving down.  Skip this.
	lda BALL_NEW_Y
	sec
	sbc #MIN_PIXEL_Y+1 
	sta THUMPER_PROXIMITY_TOP
	
; Calculate proximity left only when moving left
?Calculate_Proximity_Left
	lda ZDIR_X
	bpl ?Calculate_Proximity_Right ; Moving right.  Skip Left.
	lda BALL_NEW_X
	sec
	sbc #MIN_BALL_X+1 
	sta THUMPER_PROXIMITY_LEFT

	jmp End_Calculate_Proximity
	
; Calculate proximity right only when moving right
?Calculate_Proximity_Right
	lda #MAX_BALL_X
	sec
	sbc BALL_NEW_X
	sta THUMPER_PROXIMITY_RIGHT

End_Calculate_Proximity

	
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
	
	mDebugByte THUMPER_PROXIMITY_TOP,      1 ; XT
	
	mDebugByte THUMPER_PROXIMITY_LEFT,     4 ; XL

	mDebugByte THUMPER_PROXIMITY_RIGHT,    7 ; XR
	
	mDebugByte THUMPER_FRAME_TOP,         10 ; FT

	mDebugByte THUMPER_FRAME_LEFT,        13 ; FL
	
	mDebugByte THUMPER_FRAME_RIGHT,       16 ; FR
	
	mDebugByte THUMPER_FRAME_LIMIT_TOP,   19 ; LT
	
	mDebugByte THUMPER_FRAME_LIMIT_LEFT,  22 ; LL
	
	mDebugByte THUMPER_FRAME_LIMIT_RIGHT, 25 ; LR
	
	mDebugByte THUMPER_COLOR_TOP,         28 ; CT
	
	mDebugByte THUMPER_COLOR_LEFT,        31 ; CL
	
	mDebugByte THUMPER_COLOR_RIGHT,       34 ; CR
	
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

	lda #PM_SIZE_NORMAL ; Reset size for Players (should be 0)

	ldx #3
?Normal_PM_Size
	sta SIZEP0,x
	dex
	bpl ?Normal_PM_Size
	
	lda #~00000000   ; 00, normal size for each missile.
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
	; Set Priority with P0/P1 on top, then Playfield, then PM2/PM3 on bottom.
	;
	lda #[FIFTH_PLAYER|2]  
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
	sta PMADR_BASE2,x
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

