/**
  @file mm_createwebservice.sas
  @brief Create a Web Ready Stored Process
  @details This macro creates a Type 2 Stored Process with the macropeople
    mm_webout macro included as pre-code.

    Usage:
<code>

* compile macros ;
filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
%inc mc;

* parmcards lets us write to a text file from open code ;
filename ft15f001 temp;
parmcards4;
    * do some sas, any inputs are now already WORK tables;
    data example1 example2;
      set sashelp.class;
    run;
    * send data back;
    %webout(ARR,example1) * Array format, fast, suitable for large tables ;
    %webout(OBJ,example2) * Object format, easier to work with ;
    %webout(CLOSE)
;;;;
%mm_createwebservice(path=/meta/app/subfolder, name=testJob, code=ft15f001)

</code>


  <h4> Dependencies </h4>
  @li mm_createstp.sas
  @li mf_getuser.sas


  @param path= The full path (in SAS Metadata) where the service will be created
  @param name= Stored Process name.  Avoid spaces - testing has shown that
    the check to avoid creating multiple STPs in the same folder with the same
    name does not work when the name contains spaces.
  @param desc= The description of the service (optional)
  @param precode= Space separated list of filerefs, pointing to the code that
    needs to be attached to the beginning of the service (optional)
  @param code= Space seperated fileref(s) of the actual code to be added
  @param server= The server which will run the STP.  Server name or uri is fine.
  @param mDebug= set to 1 to show debug messages in the log


  @version 9.2
  @author Allan Bowe

**/

%macro mm_createwebservice(path=
    ,name=initService
    ,precode=
    ,code=
    ,desc=This stp was created automagically by the mm_createwebservice macro
    ,mDebug=0
    ,server=SASApp
)/*/STORE SOURCE*/;

%if &syscc ge 4 %then %do;
  %put &=syscc - &sysmacroname will not execute in this state;
  %return;
%end;

%local mD;
%if &mDebug=1 %then %let mD=;
%else %let mD=%str(*);
%&mD.put Executing mm_createwebservice.sas;
%&mD.put _local_;

%local work tmpfile;
%let work=%sysfunc(pathname(work));
%let tmpfile=__mm_createwebservice.temp;

/**
 * Add webout macro
 * These put statements are auto generated - to change the macro, change the
 * source (mm_webout) and run `build.py`
 */
data _null_;
  file "&work/&tmpfile" lrecl=3000 ;
  put "/* Created on %sysfunc(today(),datetime19.) by %mf_getuser() */";
/* WEBOUT BEGIN */
  put '/** ';
  put '  @file mm_webout.sas ';
  put '  @brief Send data to/from SAS Stored Processes ';
  put '  @details This macro should be added to the start of each Stored Process, ';
  put '  **immediately** followed by a call to: ';
  put ' ';
  put '      %webout(OPEN) ';
  put ' ';
  put '    This will read all the input data and create same-named SAS datasets in the ';
  put '    WORK library.  You can then insert your code, and send data back using the ';
  put '    following syntax: ';
  put ' ';
  put '      data some datasets; * make some data ; ';
  put '      retain some columns; ';
  put '      run; ';
  put ' ';
  put '      %webout(ARR,some)  * Array format, fast, suitable for large tables ; ';
  put '      %webout(OBJ,datasets) * Object format, easier to work with ; ';
  put ' ';
  put '     Finally, wrap everything up send some helpful system variables too ';
  put ' ';
  put '       %webout(CLOSE) ';
  put ' ';
  put ' ';
  put '  Notes: ';
  put ' ';
  put '  * The `webout()` macro is a simple wrapper for `mm_webout` to enable cross ';
  put '    platform compatibility.  It may be removed if your use case does not involve ';
  put '    SAS Viya. ';
  put ' ';
  put '  @param in= provide path or fileref to input csv ';
  put '  @param out= output path or fileref to output csv ';
  put '  @param qchar= quote char - hex code 22 is the double quote. ';
  put ' ';
  put '  @version 9.3 ';
  put '  @author Allan Bowe ';
  put ' ';
  put '**/ ';
  put '%macro mm_webout(action,ds=,_webout=_webout,fref=_temp); ';
  put '%global _webin_file_count _program _debug; ';
  put '%if &action=OPEN %then %do; ';
  put '  %if %upcase(&_debug)=LOG %then %do; ';
  put '    options mprint notes; ';
  put '  %end; ';
  put ' ';
  put '  %let _webin_file_count=%eval(&_webin_file_count+0); ';
  put '  /* setup temp ref */ ';
  put '  %if %upcase(&fref) ne _WEBOUT %then %do; ';
  put '    filename &fref temp lrecl=999999; ';
  put '  %end; ';
  put '  /* now read in the data */ ';
  put '  %local i; ';
  put '  %do i=1 %to &_webin_file_count; ';
  put '    filename indata filesrvc "&&_WEBIN_FILEURI&i"; ';
  put '    data _null_; ';
  put '      infile indata; ';
  put '      input; ';
  put '      call symputx(''input_statement'',_infile_); ';
  put '      putlog "&&_webin_name&i input statement: "  _infile_; ';
  put '      stop; ';
  put '    run; ';
  put '    data &&_webin_name&i; ';
  put '      infile indata firstobs=2 dsd termstr=crlf ; ';
  put '      input &input_statement; ';
  put '    run; ';
  put '  %end; ';
  put '  /* setup json */ ';
  put '  data _null_;file &fref; ';
  put '  %if %upcase(&_debug)=LOG %then %do; ';
  put '    put ''>>weboutBEGIN<<''; ';
  put '  %end; ';
  put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''", "data":{''; ';
  put '  run; ';
  put ' ';
  put '%end; ';
  put ' ';
  put '%else %if &action=ARR or &action=OBJ %then %do; ';
  put '  options validvarname=upcase; ';
  put ' ';
  put '  %global sasjs_tabcnt; ';
  put '  %let sasjs_tabcnt=%eval(&sasjs_tabcnt+1); ';
  put ' ';
  put '  data _null_;file &fref mod; ';
  put '    if &sasjs_tabcnt=1 then put ''"'' "&ds" ''" :''; ';
  put '    else put '', "'' "&ds" ''" :''; ';
  put '  run; ';
  put ' ';
  put '  filename _web2 temp lrecl=999999; ';
  put '  %local nokeys; ';
  put '  %if &action=ARR %then %let nokeys=nokeys; ';
  put '  proc json out=_web2; ';
  put '    export &ds / nosastags &nokeys; ';
  put '  run; ';
  put '  data _null_; ';
  put '    file &fref mod; ';
  put '    infile _web2 ; ';
  put '    input; ';
  put '    put _infile_; ';
  put '  run; ';
  put ' ';
  put '%end; ';
  put ' ';
  put '%else %if &action=CLOSE %then %do; ';
  put ' ';
  put '  /* close off json */ ';
  put '  data _null_;file &fref mod; ';
  put '    _PROGRAM=quote(trim(resolve(symget(''_PROGRAM'')))); ';
  put '    put ''},"SYSUSERID" : "'' "&sysuserid." ''",''; ';
  put '    _METAUSER=quote(trim(symget(''_METAUSER''))); ';
  put '    put ''"_METAUSER": '' _METAUSER '',''; ';
  put '    _METAPERSON=quote(trim(symget(''_METAPERSON''))); ';
  put '    put ''"_METAPERSON": '' _METAPERSON '',''; ';
  put '    put ''"_PROGRAM" : '' _PROGRAM '',''; ';
  put '    put ''"END_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''" ''; ';
  put '    put "}"; ';
  put '  %if %upcase(&_debug)=LOG %then %do; ';
  put '    put ''>>weboutEND<<''; ';
  put '  %end; ';
  put '  run; ';
  put ' ';
  put '  data _null_; ';
  put '    rc=fcopy("&fref","&_webout"); ';
  put '  run; ';
  put ' ';
  put '%end; ';
  put ' ';
  put '%mend; ';
/* WEBOUT END */
  put '%macro webout(action,ds,_webout=_webout,fref=_temp);';
  put '  %mm_webout(&action,ds=&ds,_webout=&_webout,fref=&fref)';
  put '%mend;';
  put '%webout(OPEN)';
run;

/* add precode and code */
%local x fref freflist;
%let freflist= &precode &code ;
%do x=1 %to %sysfunc(countw(&freflist));

  %let fref=%scan(&freflist,&x);
  %put &sysmacroname: adding &fref;
  data _null_;
    file "&work/&tmpfile" lrecl=3000 mod;
    infile &fref;
    input;
    put _infile_;
  run;
%end;

/* create the metadata folder if not already there */
%mm_createfolder(path=&path)
%if &syscc ge 4 %then %return;

/* create the web service */
%mm_createstp(stpname=&name
  ,filename=&tmpfile
  ,directory=&work
  ,tree=&path
  ,stpdesc=&desc
  ,mDebug=&mdebug
  ,server=&server
  ,stptype=2)

%mend;
