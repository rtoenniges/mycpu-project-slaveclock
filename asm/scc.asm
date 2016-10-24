;[ASCII]

;******************************************
;********** Slave clock control ***********
;******************************************
;*******  2016 by Robin Tönniges  *********
;******************************************

#include <sys.hsm>
#include <tsr.hsm>
#include <time.hsm> 
#include <code.hsm> 
#include <conio.hsm> 
#include <ctype.hsm>
#include <stdio.hsm>
#include <sys.hsm>


;-------------------------------------
; declare variables

DCF77LIB        EQU 60h
OUTPUT          EQU 2382h     ;Hardware adress of output byte (Clock on bit 0 & 1)

REFRESH_DELAY    SET 30       ;Timer division factor for clock sync (30 = ~1s)
IMPULS_DELAY     SET 15       ;Timer division factor for clock impuls lenght (15 = ~0,5s)

VAR_dcfLibEntry     DS    2
VAR_refreshHandle   DB    0
VAR_refreshTimerDiv DB    REFRESH_DELAY  
VAR_impulsTimerDiv  DB    IMPULS_DELAY   
VAR_startImpuls     DB    0
VAR_currentHour     DB    0
VAR_currentMinute   DB    0
VAR_bckpFileHandle  DB    0
VAR_clockChanged    DB    0

bckpFilePath        DB  "8:/etc/scc.dat",0

;Clock data will be saved in Backup-file
;-------------------------------------
BackupStart
VAR_impuls          DB    1
VAR_clockHour       DB    0
VAR_clockMinute     DB    0
BackupEnd
;-------------------------------------

BckpFileStruct
dataPtr             DS   2
dataSize            DW   BackupEnd - BackupStart


filePos0            DB   0,0,0


textHelp            DB  "\rscc [-d] [-b]\r"
                    DB  "Parameters:\r"
                    DB  "   -d use DCF77-Library\r"
                    DB  "   -b use Backupfile (will be created in 8:/etc/)\r",0
                    
textHour            DB  "\rWhich hour does the clock show? [1-12]\r",0 
textMinute          DB  "\rWhich minute does the clock show? [0-59]\r",0 
textDCFError        DB  "\rFailed to load DCF77-Lib!\r",0 
textUnknParam       DB  "\rUnknown parameter!\r"
                    DB  "scc -h for help",0
textNoBckp          DB  "\rNo backup file found!\r",0
textBckpCreated     DB  "\rNew backup file created!\r",0
textBckpCreateErr   DB  "\rError creating backup file!\r",0

textBckpReadError   DB  "\rError reading backup file!\r"
                    DB  "Try to delete 8:/etc/scc.dat\r",0
                    
textBckpWriteError  DB  "\rError writing to backup file!\r"
                    DB  "Try to delete 8:/etc/scc.dat\r",0


;-------------------------------------
; begin of assembly code

codestart
#include <tsr.hsm>

initfunc  

        ;move this program to a separate memory page
        ;LPT  #codestart
        ;LDA  #0Eh
        ;JSR  (KERN_MULTIPLEX)  ;may fail on older kernel

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
        JSR loadDCF77
        PLR
        JPC _skp3
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
        LPT #textHelp
        JSR (KERN_PRINTSTR)
        JMP _skp3
_skp4   LPT #textUnknParam
        JSR (KERN_PRINTSTR)
_skp3   LDA #1
        RTS          
   
                
init0   LDAA VAR_bckpFileHandle
        JNZ init1
        
        ;Send sync impuls
        LDA #1
        JSR imp0
                    
        ;Get clock data from user
        JSR getClock        
        
        ;Setup timer interrupt (Refresh cycle) 
init1   CLA
        LPT  #refreshInt  
        JSR  (KERN_MULTIPLEX) 
        STAA VAR_refreshHandle  ;Save adress of timerhandle
        
        CLA
        RTS
        
        
termfunc  
        ;uninstall idle function
        LPT #idle
        CLC
        JSR (KERN_SETIDLEFUNC)
   
        ;uninstall timer interrupt
        LDXA VAR_refreshHandle
        JPZ  term0
        LDA  #1
        JSR  (KERN_MULTIPLEX)  

        ;unload dcf lib
term0   LDA #DCF77LIB
        JSR (KERN_LIBUNLOAD)
        RTS

;--------------------------------------------------------- 
;Timer interrupt (Check system time, set slave clock, sync with dcf77)
;---------------------------------------------------------   
;Check system time -> set clock
refreshInt
        DECA VAR_refreshTimerDiv
        JNZ impuls
        LDA #REFRESH_DELAY
        STAA VAR_refreshTimerDiv    
        
        ;Get system time
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
        

;Generate clock impuls
impuls
        DECA VAR_impulsTimerDiv
        JNZ dcf77
        LDA #IMPULS_DELAY
        STAA VAR_impulsTimerDiv
        
        ;Set output to 0
        LDAA VAR_startImpuls
        JNZ imp0
        STZ OUTPUT
        JMP dcf77
        
        ;Set output to 10 or 01
imp0    LDAA VAR_impuls
        CMP #3
        JNZ imp1
        LDA #1
        STAA VAR_impuls
imp1    STAA OUTPUT
        INCA VAR_impuls
        STZ VAR_startImpuls
        
        ;Increment clock time
        INCA VAR_clockMinute
        LDAA VAR_clockMinute
        CMP #60
        JNZ imp2
        STZ VAR_clockMinute
        INCA VAR_clockHour
        LDAA VAR_clockHour
        CMP #13
        JNZ imp2
        SBC #12
        STAA VAR_clockHour 

imp2    LDA #1
        STAA VAR_clockChanged


;Sync system time with DCF77
dcf77
        ;DCF77-Lib loaded?
        LPT #VAR_dcfLibEntry
        LPA
        JPZ _RTS    
 
               
        ;Get seconds
        LDA #01h
        JSR (VAR_dcfLibEntry)
        JPC _RTS
        JNZ _RTS    ;Sync every minute
        TAY
        ;Get minutes
        LDA #02h
        JSR (VAR_dcfLibEntry)
        JPC _RTS
        ;JNZ _RTS    ;Sync every hour
        TAX
        ;Get hours
        LDA #03h
        JSR (VAR_dcfLibEntry)
        JPC _RTS
        ;JNZ _RTS    ;Sync every day
        
        ;Set system time
        SEC
        JSR (KERN_GETSETTIME)
        
        
        ;Get year
        LDA #07h
        JSR (VAR_dcfLibEntry)
        JPC _RTS
        TAY
        ;Get month
        LDA #06h
        JSR (VAR_dcfLibEntry)
        JPC _RTS
        TAX
        ;Get day
        LDA #04h
        JSR (VAR_dcfLibEntry)
        JPC _RTS
        
        ;Set system date
        SEC
        JSR (KERN_GETSETDATE)
        
        RTS

;--------------------------------------------------------- 
;Idle function (Save slave clock value in Backupfile)
;---------------------------------------------------------  
idle        
        LDAA VAR_clockChanged
        JPZ _RTS
        JSR writeBackup
        STZ VAR_clockChanged
        RTS
        
;--------------------------------------------------------- 
;Helper functions   
;---------------------------------------------------------  
;Load DCF77-Lib
;Carry = 0 on success
loadDCF77
        LDA #DCF77LIB
        JSR (KERN_LIBSELECT)
        JNC lL0
        LPT #textDCFError   
        JSR (KERN_PRINTSTR)
        SEC
        RTS
lL0     LDA #08h
        JSR (KERN_LIBCALL)
        SPTA VAR_dcfLibEntry
        JSR (KERN_LIBDESELECT)
        CLC
        RTS
        
;Get clock data from user
getClock
        ;Get clock hour
        LPT #textHour
        JSR (KERN_PRINTSTR)
        CLA
        CLX
        JSR (KERN_INPUT)
        JSR (KERN_STRING2NUMBER)
        STAA VAR_clockHour

        ;Get clock minute
        LPT #textMinute
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
        JNC gB2
        
        ;No backup found -> Creating one
        LPT #textNoBckp 
        JSR (KERN_PRINTSTR)
        JSR writeBackup
        JNC gB1
        LPT #textBckpCreateErr ;Error creating backup
        JSR (KERN_PRINTSTR)
        STZ VAR_bckpFileHandle
        SEC
        RTS       
gB1     LPT #textBckpCreated
        JSR (KERN_PRINTSTR)
        STZ VAR_bckpFileHandle
        
        ;Setup idle function (Backup saving)
gB2     LPT #idle
        SEC
        JSR (KERN_SETIDLEFUNC)
        CLC
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
        LPT #bckpFilePath
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
        LPT #bckpFilePath
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
rB0     JSR setBlockPtr
        JSR setFilePtr   
        LPT #BckpFileStruct
        LDAA VAR_bckpFileHandle
        CLC ;BlockRead
        JSR (KERN_FILEBLOCKRDWR)
        PHP
        JSR closeBackup
        PLP
        JNC _RTS
        LPT #textBckpReadError  ;Error reading backup
        JSR (KERN_PRINTSTR)
        SEC
        RTS

;Wirte data to Backupfile
;Carry = 0 on success
writeBackup        
        JSR openBackupRW
        JNC wB0
        RTS
wB0     JSR setBlockPtr
        JSR setFilePtr       
        LPT #BckpFileStruct
        LDAA VAR_bckpFileHandle
        SEC ;BlockWrite
        JSR (KERN_FILEBLOCKRDWR)
        PHP
        JSR closeBackup 
        PLP
        JNC _RTS     
        LPT #textBckpWriteError  ;Error writing backup
        JSR (KERN_PRINTSTR)
        SEC
        RTS
        
        
_RTS    RTS
