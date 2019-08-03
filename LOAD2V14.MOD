MODULE Load2;

FROM SHELL IMPORT Shell;
FROM CmdQuery IMPORT WithCMD,
                     CMDentry;
FROM COPYFILE IMPORT CopyFile,
                     ResponseCode;
FROM DiskServices IMPORT CalcAllocations,
                         GetDiskFreeSpace;
FROM Directories IMPORT ARCHIVE,
                        DirQuery,
                        DirEntry,
                        SetFileAttr,
                        NORMAL;
FROM FileSpec IMPORT ParseFileSpec;
FROM Files IMPORT Create,
                  Open,
                  READ,
                  Read,
                  WRITE,
                  Write,
                  Close,
                  Delete;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Strings IMPORT Append, Concat, Length, Assign;
FROM System IMPORT GetArg, Terminate, GetEnv;
FROM InOut IMPORT WriteCard,
                  WriteInt,
                  WriteLine,
                  WriteLongCard,
                  WriteString,
                  WriteLn,
                  RedirectOutput,
                  CloseOutput;
FROM XString IMPORT YesNo;
TYPE
    rListRecord = RECORD
           filename    :ARRAY [0..65] OF CHAR;
           fileattr    :BITSET;
           filetime    :CARDINAL;
           filedate    :CARDINAL;
           filesize    :LONGCARD;
           filedone    :BOOLEAN;
       END;
       taList = ARRAY [0..500] OF rListRecord;
       paList = POINTER TO taList;
VAR
    paFileList            :paList;
    iMax,
    iFileCount,
    iIndex,
    iCount,
    iNextPos,
    iFilesLeft           :INTEGER;
    axDriveName           :ARRAY [0..1] OF CHAR;
    bFlag               :BOOLEAN;
    cAllocSize,
    cSPC,
    cAC,
    cBPS,
    cCPD,
    cCount,
    cUsed,
    cRoom                :CARDINAL;

PROCEDURE Syntax( lev : INTEGER);
BEGIN
    WriteString("Syntax: LOAD2 <drive> <filespec> <filespec> ... ");
    WriteLn;
    Terminate(lev)
END Syntax;

PROCEDURE BuildList( f : DirEntry);
VAR
    iCount : INTEGER;
    bFlag : BOOLEAN;

PROCEDURE MoveDown( iFrom, iTo : INTEGER);
VAR
    iCnt : INTEGER;
    rItem : rListRecord;

BEGIN
    FOR iCnt := iFrom TO (iTo + 1) BY (-1) DO
        rItem := paFileList^[iCnt-1];
        paFileList^[iCnt] := rItem;
    END;

END MoveDown;

PROCEDURE Store( iLoc : INTEGER);
VAR
    rItem2 : rListRecord;
BEGIN

       WITH f DO
           Assign(name,rItem2.filename);
           rItem2.fileattr  := attribute;
           rItem2.filetime := time;
           rItem2.filedate := date;
           rItem2.filesize := size;
           rItem2.filedone := FALSE;
       END;
       paFileList^[iLoc] := rItem2;
       INC(iFileCount)

END Store;



BEGIN
    bFlag := FALSE;
    IF iNextPos > 0 THEN
        iCount := 0;
        LOOP
            IF iCount > (iNextPos-1) THEN
                EXIT;
            END;
            IF f.size > paFileList^[iCount].filesize THEN
                MoveDown(iNextPos,iCount);
                Store(iCount);
                bFlag := TRUE;
                EXIT;
            END;
            INC(iCount);

        END (* LOOP *);
    END (* IF *);
    IF NOT bFlag THEN
        Store(iNextPos);
    END;
    INC(iNextPos);

END BuildList;


PROCEDURE DoCopy( iIndex : INTEGER):CARDINAL;
VAR
    rListRec          :rListRecord;
    RespCode    :ResponseCode;
    sDestFile     :ARRAY [0..13] OF CHAR;
    drive       :CHAR;
    dir         :ARRAY [0..50] OF CHAR;
    name        :ARRAY [0..7] OF CHAR;
    ext         :ARRAY [0..2] OF CHAR;
BEGIN
    rListRec := paFileList^[iIndex];
    WriteString("Copying: ");
    WriteString(rListRec.filename);
    WriteString("(");
    WriteCard(CalcAllocations(rListRec.filesize,cAllocSize),1);
    WriteString(')');
    sDestFile := "";
    ParseFileSpec(rListRec.filename,drive,dir,name,ext);
    Concat(axDriveName,sDestFile,sDestFile);
    Append(sDestFile,name);
    Append(sDestFile,".");
    Append(sDestFile,ext);
    RespCode := CopyFile(rListRec.filename,sDestFile);
    IF RespCode # Successful THEN
        CASE RespCode OF
            FileNotFound :
                WriteLine("ERROR: File not found.") |
            CantOpenTarget :
                WriteLine("ERROR: Can't create destination file.") |
            CantWriteTarget :
                WriteLine("ERROR: Can't write to destination file.")
        END;
        RETURN 0
    ELSE
        rListRec.filedone := TRUE;
        paFileList^[iIndex] := rListRec;
        RETURN CalcAllocations(rListRec.filesize,cAllocSize);
    END;
END DoCopy;
PROCEDURE Process(sParam : CMDentry);
BEGIN
     DirQuery(sParam,NORMAL-ARCHIVE,BuildList);
END Process;

PROCEDURE RunEnvironmentString;
VAR
    sEnvVar,
    sCommandCom : ARRAY [0..126] OF CHAR;
    sMessage : ARRAY [0..255] OF CHAR;
    cExitCode : CARDINAL;
BEGIN
    GetEnv("LOAD2",sEnvVar);
    IF sEnvVar[0] # 0C THEN
        sMessage := "Do you want to run the command: ";
        Append(sMessage,sEnvVar);
        IF YesNo(sMessage) THEN
            IF NOT Shell(sEnvVar,cExitCode) THEN
                WriteString("Command failed. DosError=");
                WriteCard(cExitCode,1);
                WriteLn
            END;
        END;
    END;
END RunEnvironmentString;

BEGIN
    WriteLine("LOAD2 v1.4 (c) Copyright Bruce M. Axtens, 1993.");
    WriteLn;
    NEW(paFileList);
    FOR iCount := 0 TO 500 DO
        paFileList^[iCount].filedone := FALSE;
        paFileList^[iCount].filename := '';
    END;
    GetArg(axDriveName,cCount);
    IF cCount = 0 THEN
        Syntax(1);
    END;
    IF axDriveName[1] <> ":" THEN
        Syntax(1)
    END;
    axDriveName[0] := CAP(axDriveName[0]);
    iFileCount := 0;
    iNextPos := 0;
    IF NOT WithCMD(Process) THEN
        Syntax(1)
    END;
    iMax := iFileCount;
    iFilesLeft := iMax;
    WriteInt(iFileCount,1);
    WriteLine(" file/s loaded.");
    LOOP
        IF iFilesLeft <= 0 THEN
            WriteLine("No files left to load.");
            EXIT
        END;
        IF NOT YesNo("Please place diskette in drive. Continue") THEN
            EXIT
        END;
        (*IF iFilesLeft = 0 THEN
            WriteLine("No more files to be copied.");
            EXIT
        END;*)
        RunEnvironmentString;
        GetDiskFreeSpace(axDriveName,cSPC,cAC,cBPS,cCPD);
        cAllocSize := cSPC * cBPS;
        WriteLongCard(LONG(cAllocSize)*LONG(cAC),1);
        WriteString(" bytes (");
        WriteCard(cAC,1);
        WriteString(" allocations out of ");
        WriteCard(cCPD,1);
        WriteString(") available on ");
        WriteLine(axDriveName);
        bFlag := TRUE;
        IF cCPD # cAC THEN
            IF cAC = 0 THEN
                WriteLine("Disk is full.");
                bFlag := FALSE
            ELSE
                WriteLine("Disk may already contain some files.");
                bFlag := YesNo("Do you want to use this disk");
            END;
        END;
        cRoom := cAC;
        IF bFlag THEN
            FOR iIndex := 0 TO iMax DO
                IF CalcAllocations(paFileList^[iIndex].filesize,cAllocSize)
                    <= cRoom THEN
                    IF (paFileList^[iIndex].filedone = FALSE) THEN
                        cUsed := DoCopy(iIndex);
                        SetFileAttr(paFileList^[iIndex].filename,
                            paFileList^[iIndex].fileattr-ARCHIVE);
                        GetDiskFreeSpace(axDriveName,cSPC,cRoom,cBPS,cCPD);
                        WriteCard(cRoom,5);
                        WriteString(" allocations remaining on ");
                        WriteLine(axDriveName);
                        IF cRoom < 1 THEN
                            iIndex := iMax
                        ELSE
                            DEC(iFilesLeft);
                            WriteInt(iFilesLeft,1);
                            WriteLine(" files remaining to be copied.")
                        END;
                    END;
                END;
            END;
        END;
    END;
    WriteLine("Writing log of copied files to LOAD2.LOG.");
    RedirectOutput("LOAD2.LOG");
    iCount := 0;
    LOOP
        IF iCount > iMax THEN
            EXIT
        END;
        IF paFileList^[iCount].filedone THEN
            WriteLine(paFileList^[iCount].filename)
        END;
        INC(iCount)
    END;
    CloseOutput;

    WriteLine("Cleaning up.");
    DISPOSE(paFileList);
END Load2.



