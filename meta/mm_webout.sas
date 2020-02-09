/**
  @file mm_webout.sas
  @brief Send data to/from SAS Stored Processes
  @details This macro should be added to the start of each Stored Process,
  **immediately** followed by a call to:

      %webout(OPEN)

    This will read all the input data and create same-named SAS datasets in the
    WORK library.  You can then insert your code, and send data back using the
    following syntax:

      data some datasets; * make some data ;
      retain some columns;
      run;

      %webout(ARR,some)  * Array format, fast, suitable for large tables ;
      %webout(OBJ,datasets) * Object format, easier to work with ;

     Finally, wrap everything up send some helpful system variables too

       %webout(CLOSE)


  Notes:

  * The `webout()` macro is a simple wrapper for `mm_webout` to enable cross
    platform compatibility.  It may be removed if your use case does not involve
    SAS Viya.

  <h4> Dependencies </h4>
  @li mm_getstpcode.sas

  @param in= provide path or fileref to input csv
  @param out= output path or fileref to output csv
  @param qchar= quote char - hex code 22 is the double quote.

  @version 9.3
  @author Allan Bowe

**/
%macro mm_webout(action,ds=,_webout=_webout,fref=_temp);
%global _webin_file_count _program _debug;
%if &action=OPEN %then %do;
  %if &_debug ge 131 %then %do;
    options mprint notes;
  %end;

  %let _webin_file_count=%eval(&_webin_file_count+0);
  /* setup temp ref */
  %if %upcase(&fref) ne _WEBOUT %then %do;
    filename &fref temp lrecl=999999;
  %end;
  /* now read in the data */
  %local i;
  %do i=1 %to &_webin_file_count;
    filename indata filesrvc "&&_WEBIN_FILEURI&i";
    data _null_;
      infile indata;
      input;
      call symputx('input_statement',_infile_);
      putlog "&&_webin_name&i input statement: "  _infile_;
      stop;
    run;
    data &&_webin_name&i;
      infile indata firstobs=2 dsd termstr=crlf ;
      input &input_statement;
    run;
  %end;
  /* setup json */
  data _null_;file &fref;
    if symget('_debug') ge 131 then put '>>weboutBEGIN<<';
    put '{"START_DTTM" : "' "%sysfunc(datetime(),datetime19.)" '", "data":{';
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

  filename _web2 temp lrecl=999999;
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
    _METAUSER=quote(trim(symget('_METAUSER')));
    put '"_METAUSER": ' _METAUSER ',';
    _METAPERSON=quote(trim(symget('_METAPERSON')));
    put '"_METAPERSON": ' _METAPERSON ',';
    put '"_PROGRAM" : ' _PROGRAM ',';
    put '"END_DTTM" : "' "%sysfunc(datetime(),datetime19.)" '" ';
    put "}";
    if symget('_debug') ge 131 then put '>>weboutEND<<';
  run;

  %if &_debug ge 131 %then %do;
    data _null_;
      put '>>weboutEND<<';
    run;
  %end;

  data _null_;
    rc=fcopy("&fref","&_webout");
  run;

%end;

%mend;

%macro webout(action,ds,_webout=_webout,fref=_temp);

  %mm_webout(&action,ds=&ds,_webout=&_webout,fref=&fref)

%mend;