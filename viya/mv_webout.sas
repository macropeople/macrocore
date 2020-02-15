/**
  @file mv_webout.sas
  @brief Send data to/from the SAS Viya Job Execution Service
  @details This macro should be added to the start of each Job Execution
  Service, **immediately** followed by a call to:

      %webout(OPEN)

    This will read all the input data and create same-named SAS datasets in the
    WORK library.  You can then insert your code, and send data back using the
    following syntax:

      data some datasets; * make some data ;
      retain some columns;
      run;

      %webout(ARR,some)  * Array format, fast, suitable for large tables ;
      %webout(OBJ,datasets) * Object format, easier to work with ;
      %webout(CLOSE)

  Notes:

  * The `webout()` macro is a simple wrapper for `mv_webout` to enable cross
    platform compatibility.  It may be removed if your use case does not involve
    SAS 9.

  @param in= provide path or fileref to input csv
  @param out= output path or fileref to output csv
  @param qchar= quote char - hex code 22 is the double quote.

  @version Viya 3.3
  @author Allan Bowe

**/
%macro mv_webout(action,ds,_webout=_webout,fref=_temp);
%global _WEBIN_FILE_COUNT _debug _omittextlog;
%if &action=OPEN %then %do;
  %put &=_omittextlog;
  %let _WEBIN_FILE_COUNT=%eval(&_WEBIN_FILE_COUNT+0);

  %if %upcase(&_omittextlog)=FALSE %then %do;
    options mprint notes mprintnest;
  %end;

  /* setup webout */
  filename &_webout filesrvc parenturi="&SYS_JES_JOB_URI" name="_webout.json";

  /* setup temp ref */
  %if %upcase(&fref) ne _WEBOUT %then %do;
    filename &fref temp lrecl=999999;
  %end;

  /* now read in the data */
  %local i;
  %do i=1 %to &_webin_file_count;
    filename indata filesrvc "&&_WEBIN_FILEURI&i";
    data _null_;
      infile indata termstr=crlf ;
      input;
      if _n_=1 then call symputx('input_statement',_infile_);
      list;
    run;
    data &&_webin_name&i;
      infile indata firstobs=2 dsd termstr=crlf ;
      input &input_statement;
    run;
  %end;

  /* setup json */
  data _null_;file &fref;
    put '{"START_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '", "data":{';
  run;

%end;

%else %if &action=ARR or &action=OBJ %then %do;
  options validvarname=upcase;

  %global sasjs_tabcnt;
  %let sasjs_tabcnt=%eval(&sasjs_tabcnt+1);

  data _null_;file &fref mod;
    if &sasjs_tabcnt=1 then put '"' "&ds" '" :';
    else put ', "' "&ds" '" :';
  run;

  filename _web2 temp;
  %local nokeys;
  %if &action=ARR %then %let nokeys=nokeys;
  proc json out=_web2;
    export &ds / nosastags &nokeys;
  run;
  data _null_;
    file &fref mod;
    infile _web2 ;
    input;
    put _infile_;
  run;

%end;

%else %if &action=CLOSE %then %do;

  /* close off json */
  data _null_;file &fref mod;
    _PROGRAM=quote(trim(resolve(symget('_PROGRAM'))));
    put '},"SYSUSERID" : "' "&sysuserid." '",';
    SYS_JES_JOB_URI=quote(trim(resolve(symget('SYS_JES_JOB_URI'))));
    jobid=quote(scan(SYS_JES_JOB_URI,-2,'/"'));
    put '"SYS_JES_JOB_URI" : ' SYS_JES_JOB_URI ',';
    put '"X-SAS-JOBEXEC-ID" : ' jobid ',';
    put '"SYSJOBID" : "' "&sysjobid." '",';
    put '"_PROGRAM" : ' _PROGRAM ',';
    put '"END_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '" ';
    put "}";
  run;

  data _null_;
    rc=fcopy("&fref","&_webout");
  run;

%end;

%mend;
