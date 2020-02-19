/**
  @file mv_createwebservice.sas
  @brief Creates a JobExecution web service if it doesn't already exist
  @details  There are a number of steps involved in building a web service on
viya:

    %* Step 1 - load macros and obtain refresh token (must be ADMIN);
    filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
    %inc mc;
    %let client=new%sysfunc(ranuni(0));
    %let secret=MySecret;
    %mv_getapptoken(client_id=&client,client_secret=&secret)

    %* Step 2 - navigate to the url in the log and paste the access code below;
    %mv_getrefreshtoken(client_id=&client,client_secret=&secret,code=wKDZYTEPK6)
    %mv_getaccesstoken(client_id=&client,client_secret=&secret)

    %* Step 3 - Now we can create some code and add it to a web service;
    filename ft15f001 temp;
    parmcards4;
        %* do some sas, any inputs are now already WORK tables;
        data example1 example2;
          set sashelp.class;
        run;
        %* send data back;
        %webout(ARR,example1) * Array format, fast, suitable for large tables ;
        %webout(OBJ,example2) * Object format, easier to work with ;
        %webout(CLOSE)
    ;;;;
    %mv_createwebservice(path=/Public/app/common,name=appInit,code=ft15f001,replace=YES)


  Notes:
    To minimise postgres requests, output json is stored in a temporary file
    and then sent to _webout in one go at the end.

  <h4> Dependencies </h4>
  @li mf_abort.sas
  @li mv_createfolder.sas
  @li mf_getuniquelibref.sas
  @li mf_getuniquefileref.sas

  @param path= The full path (on SAS Drive) where the service will be created
  @param name= The name of the service
  @param desc= The description of the service
  @param precode= Space separated list of filerefs, pointing to the code that
    needs to be attached to the beginning of the service
  @param code= Fileref(s) of the actual code to be added
  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.
  @param replace= select YES to replace any existing service in that location


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mf_abort.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas
  @li mv_deletejes.sas

**/

%macro mv_createwebservice(path=
    ,name=
    ,desc=Created by the mv_createwebservice.sas macro
    ,precode=
    ,code=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=authorization_code
    ,replace=NO
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

%if %upcase(&replace)=YES %then %do;
  %mv_deletejes(path=&path, name=&name)
%end;
%else %do;
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
  libname &libref2 clear;
%end;

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
  put "/* Created on %sysfunc(datetime(),datetime19.) by &sysuserid */";
/* WEBOUT BEGIN */
  put '%macro mv_webout(action,ds,_webout=_webout,fref=_temp); ';
  put '%global _debug _omittextlog; ';
  put '%if &action=OPEN %then %do; ';
  put ' ';
  put '  %if %upcase(&_omittextlog)=FALSE %then %do; ';
  put '    options mprint notes mprintnest; ';
  put '  %end; ';
  put ' ';
  put '  %if %symexist(sasjs_tables) %then %do; ';
  put '    /* get the data and write to a file */ ';
  put '    filename _sasjs "%sysfunc(pathname(work))/sasjs.lua"; ';
  put '    data _null_; ';
  put '      file _sasjs; ';
  put '      put ''s=sas.symget("sasjs_tables")''; ';
  put '      put ''tablist=s:sub(8,s:len()-1)''; ';
  put '      put ''t=sas.countw(tablist)''; ';
  put '      put ''for i = 1,t ''; ';
  put '      put ''do ''; ';
  put '      put ''  tab=sas.scan(tablist,i)''; ';
  put '      put ''  sasdata=""''; ';
  put '      put ''  if (sas.symexist("sasjs"..i.."data0")==0)''; ';
  put '      put ''  then''; ';
  put '      put ''    s=sas.symget("sasjs"..i.."data")''; ';
  put '      put ''    sasdata=s:sub(8,s:len()-1)''; ';
  put '      put ''  else''; ';
  put '      put ''    for d = 1, sas.symget("sasjs"..i.."data0")''; ';
  put '      put ''    do''; ';
  put '      put ''      s=sas.symget("sasjs"..i.."data"..d)''; ';
  put '      put ''      sasdata=sasdata..s:sub(8,s:len()-1)''; ';
  put '      put ''    end''; ';
  put '      put ''  end''; ';
  put '      put ''  file = io.open(sas.pathname("work").."/"..tab..".csv", "a")''; ';
  put '      put ''  io.output(file)''; ';
  put '      put ''  io.write(sasdata)''; ';
  put '      put ''  io.close(file)''; ';
  put '      put ''end''; ';
  put '    run; ';
  put '    %inc _sasjs; ';
  put ' ';
  put '    /* now read in the data */ ';
  put '    %local i; %do i=1 %to %sysfunc(countw(&sasjs_tables)); ';
  put '      %local table; %let table=%scan(&sasjs_tables,&i); ';
  put '      data _null_; ';
  put '        infile "%sysfunc(pathname(work))/&table..csv" termstr=crlf ; ';
  put '        input; ';
  put '        if _n_=1 then call symputx(''input_statement'',_infile_); ';
  put '        list; ';
  put '      data &table; ';
  put '        infile "%sysfunc(pathname(work))/&table..csv" firstobs=2 dsd termstr=crlf; ';
  put '        input &input_statement; ';
  put '      run; ';
  put '    %end; ';
  put '  %end; ';
  put ' ';
  put '  /* setup webout */ ';
  put '  filename &_webout filesrvc parenturi="&SYS_JES_JOB_URI" name="_webout.json"; ';
  put ' ';
  put '  /* setup temp ref */ ';
  put '  %if %upcase(&fref) ne _WEBOUT %then %do; ';
  put '    filename &fref temp lrecl=999999; ';
  put '  %end; ';
  put ' ';
  put '  /* setup json */ ';
  put '  data _null_;file &fref; ';
  put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"''; ';
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
  put '    put '', "'' "%lowcase(&ds)" ''" :{"data":''; ';
  put ' ';
  put '  proc sort data=sashelp.vcolumn(where=(libname=''WORK'' & memname="%upcase(&ds)")) ';
  put '    out=_data_; ';
  put '    by varnum; ';
  put ' ';
  put '  data _null_; set &syslast end=last; ';
  put '    call symputx(cats(''name'',_n_),name,''l''); ';
  put '    call symputx(cats(''type'',_n_),type,''l''); ';
  put '    if last then call symputx(''cols'',_n_,''l''); ';
  put ' ';
  put '  data _null_; file &fref dsd mod; ';
  put '    set &ds; ';
  put '    if _n_>1 then put "," @; ';
  put '    put ';
  put '    %if &action=ARR %then "[" ; %else "{" ; ';
  put '    %local c; %do c=1 %to &cols; ';
  put '      %if &action=OBJ %then """&&name&c"":" ; ';
  put '       &&name&c ';
  put '      %if &&type&c=char %then  ~ ; ';
  put '    %end; ';
  put '    %if &action=ARR %then "]" ; %else "}" ; ; ';
  put ' ';
  put '  data _null_; file &fref mod; ';
  put '    put "]}"; ';
  put '  run; ';
  put ' ';
  put '%end; ';
  put ' ';
  put '%else %if &action=CLOSE %then %do; ';
  put ' ';
  put '  /* close off json */ ';
  put '  data _null_;file &fref mod; ';
  put '    _PROGRAM=quote(trim(resolve(symget(''_PROGRAM'')))); ';
  put '    put '',"SYSUSERID" : "'' "&sysuserid." ''",''; ';
  put '    SYS_JES_JOB_URI=quote(trim(resolve(symget(''SYS_JES_JOB_URI'')))); ';
  put '    jobid=quote(scan(SYS_JES_JOB_URI,-2,''/"'')); ';
  put '    put ''"SYS_JES_JOB_URI" : '' SYS_JES_JOB_URI '',''; ';
  put '    put ''"X-SAS-JOBEXEC-ID" : '' jobid '',''; ';
  put '    put ''"SYSJOBID" : "'' "&sysjobid." ''",''; ';
  put '    put ''"_PROGRAM" : '' _PROGRAM '',''; ';
  put '    put ''"END_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''" ''; ';
  put '    put "}"; ';
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
  put '  %mv_webout(&action,ds=&ds,_webout=&_webout,fref=&fref)';
  put '%mend;';
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
libname &libref1 clear;


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

%put NOTE: &sysmacroname: Job &name successfully created in &path;
%put NOTE-;
%put NOTE- Check it out here:;
%put NOTE-;
%put NOTE- &url/SASJobExecution?_PROGRAM=&path/&name;
%put NOTE-;

%mend;
