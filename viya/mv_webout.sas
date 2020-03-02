/**
  @file mv_webout.sas
  @brief Send data to/from the SAS Viya Job Execution Service
  @details This macro should be added to the start of each Job Execution
  Service, **immediately** followed by a call to:

        %mv_webout(FETCH)

    This will read all the input data and create same-named SAS datasets in the
    WORK library.  You can then insert your code, and send data back using the
    following syntax:

        data some datasets; * make some data ;
        retain some columns;
        run;

        %mv_webout(OPEN)
        %mv_webout(ARR,some)  * Array format, fast, suitable for large tables ;
        %mv_webout(OBJ,datasets) * Object format, easier to work with ;
        %mv_webout(CLOSE)


  @param action Either OPEN, ARR, OBJ or CLOSE
  @param ds The dataset to send back to the frontend
  @param _webout= fileref for returning the json
  @param fref= temp fref

  @version Viya 3.3
  @author Allan Bowe

**/
%macro mv_webout(action,ds,_webout=_webout,fref=_temp);
%global _debug _omittextlog;
%let action=%upcase(&action);

%if &action=FETCH %then %do;

  %if %upcase(&_omittextlog)=FALSE %then %do;
    options mprint notes mprintnest;
  %end;

  %if %symexist(sasjs_tables) %then %do;
    /* get the data and write to a file */
    filename _sasjs "%sysfunc(pathname(work))/sasjs.lua";
    data _null_;
      file _sasjs;
      put 's=sas.symget("sasjs_tables")';
      put 'if(s:sub(1,7) == "%nrstr(")';
      put 'then';
      put ' tablist=s:sub(8,s:len()-1)';
      put 'else';
      put ' tablist=s';
      put 'end';
      put 'for i = 1,sas.countw(tablist) ';
      put 'do ';
      put '  tab=sas.scan(tablist,i)';
      put '  sasdata=""';
      put '  if (sas.symexist("sasjs"..i.."data0")==0)';
      put '  then';
      put '    s=sas.symget("sasjs"..i.."data")';
      put '    sasdata=s:sub(8,s:len()-1)';
      put '  else';
      put '    for d = 1, sas.symget("sasjs"..i.."data0")';
      put '    do';
      put '      s=sas.symget("sasjs"..i.."data"..d)';
      put '      sasdata=sasdata..s:sub(8,s:len()-1)';
      put '    end';
      put '  end';
      put '  file = io.open(sas.pathname("work").."/"..tab..".csv", "a")';
      put '  io.output(file)';
      put '  io.write(sasdata)';
      put '  io.close(file)';
      put 'end';
    run;
    %inc _sasjs;

    /* now read in the data */
    %local i; %do i=1 %to %sysfunc(countw(&sasjs_tables));
      %local table; %let table=%scan(&sasjs_tables,&i);
      data _null_;
        infile "%sysfunc(pathname(work))/&table..csv" termstr=crlf ;
        input;
        if _n_=1 then call symputx('input_statement',_infile_);
        list;
      data &table;
        infile "%sysfunc(pathname(work))/&table..csv" firstobs=2 dsd termstr=crlf;
        input &input_statement;
      run;
    %end;
  %end;

  /* setup webout */
  filename &_webout filesrvc parenturi="&SYS_JES_JOB_URI"
    name="_webout.json" lrecl=999999 ;

  /* setup temp ref */
  %if %upcase(&fref) ne _WEBOUT %then %do;
    filename &fref temp lrecl=999999;
  %end;

%end;

%else %if &action=OPEN %then %do;
  /* setup json */
  data _null_;file &fref;
    put '{"START_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '"';
  run;

%end;

%else %if &action=ARR or &action=OBJ %then %do;
  options validvarname=upcase;

  data _null_;file &fref mod;
    put ", ""%lowcase(&ds)"":[";

  proc sort data=sashelp.vcolumn
      (where=(upcase(libname)='WORK' & upcase(memname)="%upcase(&ds)"))
    out=_data_;
    by varnum;

  data _null_; set _last_ end=last;
    call symputx(cats('name',_n_),name,'l');
    call symputx(cats('type',_n_),type,'l');
    call symputx(cats('len',_n_),length,'l');
    if last then call symputx('cols',_n_,'l');

  proc format; /* credit yabwon for special null removal */
    value bart ._ - .z = null
    other = [best.];

  data _null_; file &fref mod lrecl=131068 ;
    set &ds;
    format _numeric_ ;
    if _n_>1 then put "," @; put
    %if &action=ARR %then "[" ; %else "{" ;
    %local c; %do c=1 %to &cols;
      %if &c>1 %then  "," ;
      %if &action=OBJ %then """&&name&c"":" ;
       &&name&c
      %if &&type&c=char %then $quote%eval(&&len&c+2). ;
      %else bart. ;
      +(0)
    %end;
    %if &action=ARR %then "]" ; %else "}" ; ;

  data _null_; file &fref mod;
    put "]";
  run;

%end;

%else %if &action=CLOSE %then %do;

  /* close off json */
  data _null_;file &fref mod;
    _PROGRAM=quote(trim(resolve(symget('_PROGRAM'))));
    put ',"SYSUSERID" : "' "&sysuserid." '",';
    SYS_JES_JOB_URI=quote(trim(resolve(symget('SYS_JES_JOB_URI'))));
    jobid=quote(scan(SYS_JES_JOB_URI,-2,'/"'));
    put '"SYS_JES_JOB_URI" : ' SYS_JES_JOB_URI ',';
    put '"X-SAS-JOBEXEC-ID" : ' jobid ',';
    put '"SYSJOBID" : "' "&sysjobid." '",';
    put '"_PROGRAM" : ' _PROGRAM ',';
    put '"END_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '" ';
    put "}";

  data _null_;
    rc=fcopy("&fref","&_webout");
  run;

%end;

%mend;
