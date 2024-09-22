;[ASCII]

;******************************************
;********** Slave clock control ***********
;******************************************
;***** by Robin Tönniges (2016-2024) ******
;******************************************

#include <sys.hsm>
#include <time.hsm> 
#include <code.hsm> 
#include <conio.hsm> 
#include <ctype.hsm>
#include <stdio.hsm>

;Comment this line in if library should load on higher ROM-Page
#DEFINE HIGH_ROM 

ORG 8000h
 DW 8002h
 DW initfunc
 DW termfunc
 DW codestart
;-------------------------------------
; declare variables

LIB_DCF77           EQU 60h
HDW_OUTPUT          EQU 3000h     ;Hardware adress of SCC-Board (Clock on bit 0 & 1)

PAR_REFRESH_DELAY   SET 7        ;Timer division factor for refresh cycle (7 = ~250ms)
PAR_IMPULS_DELAY    SET 15       ;Timer division factor for clock impuls lenght (15 = ~0,5s)

VAR_refreshHandle   DB    0
VAR_refreshTimerDiv DB    PAR_REFRESH_DELAY  
VAR_impulsTimerDiv  DB    PAR_IMPULS_DELAY   
VAR_startImpuls     DB    0
VAR_currentHour     DB    0
VAR_currentMinute   DB    0
VAR_bckpFileHandle  DW    0
VAR_clockChanged    DB    0

FLG_timerInt        DW    0


PAR_bckpFilePath        DB  "8:/etc/scc.dat",0

;Clock data will be saved in Backup-file
;-------------------------------------
BackupStart
VAR_impuls          DB    1
VAR_clockHour       DB    0
VAR_clockMinute     DB    0
BackupEnd
;-------------------------------------

BckpFileStruct
dataPtr             DW   BackupStart
dataSize            DW   BackupEnd - BackupStart

filePos0            DB   0,0,0


STR_textHelp        DB  "\rscc [-d] [-b]\r"
                    DB  "Parameters:\r"
                    DB  "   -d use DCF77-Library\r"
                    DB  "   -b use Backupfile (will be created in 8:/etc/)\r",0
                    
STR_textHour        DB  "\rWhich hour does the clock show? [1-12]\r",0 
STR_textMinute      DB  "\rWhich minute does the clock show? [0-59]\r",0 
STR_textDCFError    DB  "\rFailed to load DCF77-Lib!\r",0 
STR_textUnknParam   DB  "\rUnknown parameter!\r"
                    DB  "scc -h for help",0
					
STR_textNoBckp      DB  "\rNo backup file found!\r",0
STR_textBckpCreated DB  "\rNew backup file created!\r",0

STR_textBckpCreateErr   DB  "\rError creating backup file!\r",0

STR_textBckpReadError   DB  "\rError reading backup file!\r"
                        DB  "Try to delete 8:/etc/scc.dat\r",0
                    
STR_textBckpWriteError  DB  "\rError writing to backup file!\r"
                        DB  "Try to delete 8:/etc/scc.dat\r",0


;-------------------------------------
; begin of assembly code

codestart

;TSR initialization
;---------------------------------------------------------  
initfunc  
        CLC
        JSR (KERN_ISLOADED)
        CLA
        JPC _RTS
		
#IFDEF HIGH_ROM
		;move this program to a separate memory page
		LPT  #codestart
		LDA  #0Eh
		JSR  (KERN_MULTIPLEX)  ;may fail on older kernel
#ENDIF

;Get parameter from console
        LDX #29h
        LDY #07h
     
skipPar LPA    
        JPZ init0
        CMP #20h
        JNZ skipPar
        
_skp0   LPA
        JPZ init0
        CMP #20h
        JPZ _skp0
        
        CMP #2Dh    
        JNZ init0
        LPA         ;'-' found
        JPZ init0
        CMP #'d'    ;Parameter -d means with DCF77-Lib
        JNZ _skp1
        PHR
        
        LDA #LIB_DCF77
        JSR (KERN_LIBSELECT)
        JNC _skp5
        LPT #STR_textDCFError   
        JSR (KERN_PRINTSTR)
		
_skp5   PLR
        JMP _skp0
		
_skp1   CMP #'b'    ;Parameter -b means with Backupfile
        JNZ _skp2
        PHR
        JSR getBackup
        PLR
        JPC _skp3
        JMP _skp0
		
_skp2   CMP #'h'    ;Parameter -h means show help
        JNZ _skp4
        LPT #STR_textHelp
        JSR (KERN_PRINTSTR)
        JMP _skp3
_skp4   LPT #STR_textUnknParam
        JSR (KERN_PRINTSTR)
_skp3   LDA #1 ;Error leave program
        RTS          
   
                
init0   LDAA VAR_bckpFileHandle+1
        JNZ init1
        LDAA VAR_bckpFileHandle
		STAA VAR_bckpFileHandle+1
		
        ;Send sync impuls
        LDA #1
        JSR imp0
                    
        ;Get clock data from user
        JSR getClock        
        
        
init1   LPT #idle ;Setup idle function
        SEC
        JSR (KERN_SETIDLEFUNC)

        CLA ;Setup timer interrupt (Refresh cycle) 
        LPT  #refreshInt  
        JSR  (KERN_MULTIPLEX) 
        STAA VAR_refreshHandle  ;Save adress of timerhandle
        
        CLA  ;return zero (success, TSR stays resistent in memory)
        JMP (KERN_EXITTSR)
       
	   
;Termination function
;---------------------------------------------------------          
termfunc  
        ;uninstall idle function
        LPT #idle
        CLC
        JSR (KERN_SETIDLEFUNC)
   
        ;uninstall timer interrupt
        LDXA VAR_refreshHandle
        JPZ  _term0
        LDA  #1
        JSR  (KERN_MULTIPLEX)  

        ;unload dcf lib
_term0  ;LDA #LIB_DCF77
        ;JSR (KERN_LIBUNLOAD)
        
        ;set outputs to zero
        LDAA HDW_OUTPUT
        AND #FCh
        STAA HDW_OUTPUT
        RTS

;--------------------------------------------------------- 
;Timer interrupt
;---------------------------------------------------------   
;Check system time -> set clock
refreshInt
        DECA VAR_refreshTimerDiv
        JNZ impuls
        LDA #PAR_REFRESH_DELAY
        STAA VAR_refreshTimerDiv    
        LDA #1
		STAA FLG_timerInt

;Generate clock impuls
impuls
        DECA VAR_impulsTimerDiv
        JNZ _RTS
        LDA #PAR_IMPULS_DELAY
        STAA VAR_impulsTimerDiv
        LDA #1
		STAA FLG_timerInt+1		

        RTS

;--------------------------------------------------------- 
;Idle function
;---------------------------------------------------------  
idle        
        ;Write to backup file
		LDAA VAR_bckpFileHandle
        JPZ ref
		LDAA VAR_clockChanged
        JPZ ref
        JSR writeBackup
        STZA VAR_clockChanged
		
;Get system time
ref     LDAA FLG_timerInt
		JPZ imp
		STZA FLG_timerInt
        CLC
        JSR (KERN_GETSETTIME)
        CMP #13
        JNC ref0
        ;Hour is greater than 12 -> subtract 12
        SBC #12
ref0    STAA VAR_currentHour
        STXA VAR_currentMinute
        
        ;Compare clock and system time
        LDAA VAR_currentHour
        CMPA VAR_clockHour
        JNZ ref1
        LDAA VAR_currentMinute
        CMPA VAR_clockMinute
        JPZ impuls
ref1    LDA #1
        STAA VAR_startImpuls

;Clock Impuls
imp     ;Set HDW_OUTPUT to 0
        LDAA FLG_timerInt+1
		JPZ _RTS
		STZA FLG_timerInt+1
		LDAA VAR_startImpuls
        JNZ imp0
        LDAA HDW_OUTPUT
        AND #FCh
        STAA HDW_OUTPUT
        RTS
        
        ;Set HDW_OUTPUT to 10 or 01
imp0    LDAA VAR_impuls
        CMP #3
        JNZ imp1
        LDA #1
        STAA VAR_impuls
imp1    LDAA HDW_OUTPUT
        AND #FCh
        ORAA VAR_impuls
        STAA HDW_OUTPUT
        INCA VAR_impuls
        STZA VAR_startImpuls
        
        ;Increment clock time
        INCA VAR_clockMinute
        LDAA VAR_clockMinute
        CMP #60
        JNZ imp2
        STZA VAR_clockMinute
        INCA VAR_clockHour
        LDAA VAR_clockHour
        CMP #13
        JNZ imp2
        SBC #12
        STAA VAR_clockHour 

imp2    LDA #1
        STAA VAR_clockChanged
		
		RTS
       
;--------------------------------------------------------- 
;Helper functions   
;---------------------------------------------------------  
        
;Get clock data from user
getClock
        ;Get clock hour
        LPT #STR_textHour
        JSR (KERN_PRINTSTR)
        CLA
        CLX
        JSR (KERN_INPUT)
        JSR (KERN_STRING2NUMBER)
        STAA VAR_clockHour

        ;Get clock minute
        LPT #STR_textMinute
        JSR (KERN_PRINTSTR)
        CLA
        CLX
        JSR (KERN_INPUT)
        JSR (KERN_STRING2NUMBER)
        STAA VAR_clockMinute
        
        RTS

;Check if backup file exists
;Carry = 0 on success
getBackup         
        JSR readBackup
        JPC gB0
        LDAA VAR_bckpFileHandle
		STAA VAR_bckpFileHandle+1
		JMP gB2
		
        ;No backup found -> Creating one
gB0     LPT #STR_textNoBckp 
        JSR (KERN_PRINTSTR)
        JSR writeBackup
        JNC gB1
        LPT #STR_textBckpCreateErr ;Error creating backup
        JSR (KERN_PRINTSTR)
        STZA VAR_bckpFileHandle
        SEC
        RTS       
		
gB1     LPT #STR_textBckpCreated
        JSR (KERN_PRINTSTR)
		
gB2     CLC
        RTS

;Set pointer to backup data
setBlockPtr
        LPT #BackupStart
        SPTA dataPtr
        LDA #BackupEnd - BackupStart
        STAA dataSize
        RTS
     
;Set filepointer to first position   
setFilePtr       
        LPT #filePos0
        LDAA VAR_bckpFileHandle
        SEC
        JSR (KERN_FTELLSEEK)
        RTS
        
;Open Backupfile (Read only)
;Carry = 0 on success
openBackupRD 
        LPT #PAR_bckpFilePath
        LDA #FOPEN_RD
        JSR (KERN_FOPEN)
        STAA VAR_bckpFileHandle
        TAX
        JNZ oBRD0
        SEC
        SKA
oBRD0   CLC
        RTS
        
;Open Backupfile (Read/Write)        
;Carry = 0 on success        
openBackupRW        
        LPT #PAR_bckpFilePath
        LDA #FOPEN_RW
        JSR (KERN_FOPEN)
        STAA VAR_bckpFileHandle
        TAX
        JNZ oBRW0
        SEC
        SKA
oBRW0   CLC
        RTS
     
;Close Backupfile   
closeBackup
        LDAA VAR_bckpFileHandle
        JSR (KERN_FCLOSE)
        RTS

;Read data from Backupfile
;Carry = 0 on success
readBackup
        JSR openBackupRD
        JNC rB0
        RTS
rB0     ;JSR setBlockPtr
        JSR setFilePtr   
        LPT #BckpFileStruct
        LDAA VAR_bckpFileHandle
        CLC ;BlockRead
        JSR (KERN_FILEBLOCKRDWR)
        PHP
        JSR closeBackup
        PLP
        JNC _RTS
        LPT #STR_textBckpReadError  ;Error reading backup
        JSR (KERN_PRINTSTR)
        SEC
        RTS

;Write data to Backupfile
;Carry = 0 on success
writeBackup        
        JSR openBackupRW
        JNC wB0
        RTS
wB0     ;JSR setBlockPtr
        JSR setFilePtr       
        LPT #BckpFileStruct
        LDAA VAR_bckpFileHandle
        SEC ;BlockWrite
        JSR (KERN_FILEBLOCKRDWR)
        PHP
        JSR closeBackup 
        PLP
        JNC _RTS     
        LPT #STR_textBckpWriteError  ;Error writing backup
        JSR (KERN_PRINTSTR)
        SEC
        RTS
        
        
_RTS    RTS
