/**
  @file mv_createwebservice.sas
  @brief Creates a JobExecution web service if it doesn't already exist
  @details For efficiency, minimise the number of calls to _webout.  In Viya this
    is stored in a database before being sent to the browser, so it's better to
    write it elsewhere and then send it all in one go.

  Step 0 - load macros if not already loaded

    filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
    %inc mc;

  Step 1 - obtain refresh token:

    %let client=someclient;
    %let secret=MySecret;
    %mv_getapptoken(client_id=&client,client_secret=&secret)

  Step 2 - navigate to the url in the log and paste the access code below

    %mv_getrefreshtoken(client_id=&client,client_secret=&secret,code=wKDZYTEPK6)
    %mv_getaccesstoken(client_id=&client,client_secret=&secret)

  Step 3 - Now we can create some code and add it to a web service

filename ft15f001 temp;
parmcards4;
      * enter sas backend code below ;
      data example1 example2;
        set sashelp.class;
      run;

      %webout(ARR,example1) * Array format, fast, suitable for large tables ;
      %webout(OBJ,example2) * Object format, easier to work with ;
      %webout(CLOSE)
;;;;
    %mv_createwebservice(path=/Public/myapp, name=testJob, code=ft15f001)

  <h4> Dependencies </h4>
  @li mf_abort.sas
  @li mv_createfolder.sas
  @li mf_getuniquelibref.sas
  @li mf_getuniquefileref.sas

  @param path= The full path where the service will be created
  @param name= The name of the service
  @param desc= The description of the service
  @param precode= Space separated list of filerefs, pointing to the code that
    needs to be attached to the beginning of the service
  @param code= Fileref(s) of the actual code to be added
  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mf_abort.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas

**/

%macro mv_createwebservice(path=
    ,name=
    ,desc=Created by the mv_createwebservice.sas macro
    ,precode=
    ,code=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=authorization_code
  );
/* initial validation checking */
%mf_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mf_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mf_abort(iftrue=(%mf_isblank(&name)=1)
  ,mac=&sysmacroname
  ,msg=%str(name value must be provided)
)
%mf_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;

/* ensure folder exists */
%put &sysmacroname: Path &path being checked / created;
%mv_createfolder(path=&path)

/* fetching folder details for provided path */
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1
  url="http://localhost/folders/folders/@item?path=&path";
  headers "Authorization"="Bearer &&&access_token_var";
run;
/*data _null_;infile &fname1;input;putlog _infile_;run;*/
%mf_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200)
  ,mac=&sysmacroname
  ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
)

/* path exists. Grab follow on link to check members */
%local libref1;
%let libref1=%mf_getuniquelibref();
libname &libref1 JSON fileref=&fname1;
data _null_;
  set &libref1..links;
  if rel='members' then call symputx('membercheck',quote(trim(href)),'l');
  else if rel='self' then call symputx('parentFolderUri',href,'l');
run;
data _null_;
  set &libref1..root;
  call symputx('folderid',id,'l');
run;
%local fname2;
%let fname2=%mf_getuniquefileref();
proc http method='GET'
    out=&fname2
    url=%unquote(%superq(membercheck));
    headers "Authorization"="Bearer &&&access_token_var"
            'Accept'='application/vnd.sas.collection+json'
            'Accept-Language'='string';
run;
/*data _null_;infile &fname2;input;putlog _infile_;run;*/
%mf_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200)
  ,mac=&sysmacroname
  ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
)

/* check that job does not already exist in that folder */
%local libref2;
%let libref2=%mf_getuniquelibref();
libname &libref2 JSON fileref=&fname2;
%local exists; %let exists=0;
data _null_;
  set &libref2..items;
  if contenttype='jobDefinition' and upcase(name)="%upcase(&name)" then
    call symputx('exists',1,'l');
run;
%mf_abort(iftrue=(&exists=1)
  ,mac=&sysmacroname
  ,msg=%str(Job &name already exists in &path)
)

/* set up the body of the request to create the service */
%local fname3;
%let fname3=%mf_getuniquefileref();
data _null_;
  file &fname3 TERMSTR=' ';
  string=cats('{"version": 0,"name":"'
  	,"&name"
  	,'","type":"Compute","parameters":[{"name":"_addjesbeginendmacros"'
    ,',"type":"CHARACTER","defaultValue":"false"}]'
    ,',"code":"');
  put string;
run;

/**
 * Add webout macro
 * These put statements are auto generated - to change the macro, change the
 * source (mv_webout) and run `build.py`
 */
%local setup;
%let setup=%mf_getuniquefileref();
data _null_;
  file &setup;
  put "/* Created on %sysfunc(today(),datetime19.) by &sysuserid */";
/* WEBOUT BEGIN */
  put '/** ';
  put '  @file mv_webout.sas ';
  put '  @brief Send data to/from the SAS Viya Job Execution Service ';
  put '  @details This macro should be added to the start of each Job Execution ';
  put '  Service, **immediately** followed by a call to: ';
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
  put '      %webout(CLOSE) ';
  put ' ';
  put '  Notes: ';
  put ' ';
  put '  * The `webout()` macro is a simple wrapper for `mv_webout` to enable cross ';
  put '    platform compatibility.  It may be removed if your use case does not involve ';
  put '    SAS 9. ';
  put ' ';
  put '  @param in= provide path or fileref to input csv ';
  put '  @param out= output path or fileref to output csv ';
  put '  @param qchar= quote char - hex code 22 is the double quote. ';
  put ' ';
  put '  @version Viya 3.3 ';
  put '  @author Allan Bowe ';
  put ' ';
  put '**/ ';
  put '%macro mv_webout(action,ds=,_webout=_webout,fref=_temp); ';
  put ' ';
  put '%if &action=OPEN %then %do; ';
  put '  %global _WEBIN_FILE_COUNT; ';
  put '  %let _WEBIN_FILE_COUNT=%eval(&_WEBIN_FILE_COUNT+0); ';
  put ' ';
  put '  /* setup webout */ ';
  put '  filename &_webout filesrvc parenturi="&SYS_JES_JOB_URI" name="_webout.json"; ';
  put ' ';
  put '  /* setup temp ref */ ';
  put '  %if %upcase(&fref) ne _WEBOUT %then %do; ';
  put '    filename &fref temp lrecl=999999; ';
  put '  %end; ';
  put ' ';
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
  put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime19.)" ''", "data":{''; ';
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
  put '  filename _web2 temp; ';
  put '  proc json out=_web2;export &ds / nosastags;run; ';
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
  put '    SYS_JES_JOB_URI=quote(trim(resolve(symget(''SYS_JES_JOB_URI'')))); ';
  put '    jobid=quote(scan(SYS_JES_JOB_URI,-2,''/"'')); ';
  put '    put ''"SYS_JES_JOB_URI" : '' SYS_JES_JOB_URI '',''; ';
  put '    put ''"X-SAS-JOBEXEC-ID" : '' jobid '',''; ';
  put '    put ''"SYSJOBID" : "'' "&sysjobid." ''",''; ';
  put '    put ''"_PROGRAM" : '' _PROGRAM '',''; ';
  put '    put ''"END_DTTM" : "'' "%sysfunc(datetime(),datetime19.)" ''" ''; ';
  put '    put "}"; ';
  put '  run; ';
  put ' ';
  put '  data _null_; ';
  put '    rc=fcopy("&fref","&_webout"); ';
  put '  run; ';
  put ' ';
  put '%end; ';
  put ' ';
  put '%mend; ';
  put ' ';
  put '%macro webout(action,ds=,_webout=_webout,fref=_temp); ';
  put ' ';
  put '  %mv_webout(&action,ds=&ds,_webout=&_webout,fref=&fref) ';
  put ' ';
  put '%mend; ';
/* WEBOUT END */
  put '%webout(OPEN)';
run;

/* insert the code, escaping double quotes and carriage returns */
%local x fref freflist;
%let freflist= &setup &precode &code ;
%do x=1 %to %sysfunc(countw(&freflist));
  %let fref=%scan(&freflist,&x);
  %put &sysmacroname: adding &fref;
  data _null_;
    length filein 8 fileid 8;
    filein = fopen("&fref","I",1,"B");
    fileid = fopen("&fname3","A",1,"B");
    rec = "20"x;
    do while(fread(filein)=0);
      rc = fget(filein,rec,1);
      if rec='"' then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'"');rc =fwrite(fileid);
      end;
      else if rec='0A'x then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'r');rc =fwrite(fileid);
      end;
      else if rec='0D'x then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'n');rc =fwrite(fileid);
      end;
      else if rec='09'x then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'t');rc =fwrite(fileid);
      end;
      else if rec='5C'x then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'\');rc =fwrite(fileid);
      end;
      else do;
        rc =fput(fileid,rec);
        rc =fwrite(fileid);
      end;
    end;
    rc=fclose(filein);
    rc=fclose(fileid);
  run;
%end;

/* finish off the body of the code file loaded to JES */
data _null_;
  file &fname3 mod TERMSTR=' ';
  put '"}';
run;

/* now we can create the job!! */
%local fname4;
%let fname4=%mf_getuniquefileref();
proc http method='POST'
    in=&fname3
    out=&fname4
    url="/jobDefinitions/definitions?parentFolderUri=&parentFolderUri";
    headers 'Content-Type'='application/vnd.sas.job.definition+json'
            "Authorization"="Bearer &&&access_token_var"
            "Accept"="application/vnd.sas.job.definition+json";
run;
data _null_;infile &fname4;input;putlog _infile_;run;
%mf_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 201)
  ,mac=&sysmacroname
  ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
)
/* clear refs */
filename &fname1 clear;
filename &fname2 clear;
filename &fname3 clear;
filename &fname4 clear;
filename &setup clear;
filename &teardown clear;
libname &libref1 clear;
libname &libref2 clear;

/* get the url so we can give a helpful log message */
%local url;
data _null_;
  if symexist('_baseurl') then do;
    url=symget('_baseurl');
    if subpad(url,length(url)-9,9)='SASStudio'
      then url=substr(url,1,length(url)-11);
    else url="&systcpiphostname";
  end;
  else url="&systcpiphostname";
  call symputx('url',url);
run;

%put &sysmacroname: Job &name successfully created in &path;
%put ;
%put Check it out here:;
%put ;
%put &url/SASJobExecution?_PROGRAM=&path/&name;
%put ;

%mend;
