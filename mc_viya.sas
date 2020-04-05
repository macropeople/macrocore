/**
  @file mv_createfolder.sas
  @brief Creates a viya folder if that foloder does not already exist
  @details Expects oauth token in a global macro variable (default
    ACCESS_TOKEN).

    options mprint;
    %mv_createfolder(path=/Public)


  @param path= The full path of the folder to be created
  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas

**/

%macro mv_createfolder(path=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=authorization_code
  );

%mp_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)

%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;

%local subfolder_cnt; /* determine the number of subfolders */
%let subfolder_cnt=%sysfunc(countw(&path,/));

%local href; /* resource address (none for root) */
%let href="/folders/folders?parentFolderUri=/folders/folders/none";

%local x newpath subfolder;
%do x=1 %to &subfolder_cnt;
  %let subfolder=%scan(&path,&x,%str(/));
  %let newpath=&newpath/&subfolder;

  %local fname1;
  %let fname1=%mf_getuniquefileref();

  %put &sysmacroname checking to see if &newpath exists;
  proc http method='GET' out=&fname1
      url="http://localhost/folders/folders/@item?path=&newpath";
      headers "Authorization"="Bearer &&&access_token_var";
  run;
  data _null_;infile &fname1;input;putlog _infile_;run;
  %local libref1;
  %let libref1=%mf_getuniquelibref();
  libname &libref1 JSON fileref=&fname1;
  %mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200 and &SYS_PROCHTTP_STATUS_CODE ne 404)
    ,mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
  %if &SYS_PROCHTTP_STATUS_CODE=200 %then %do;
    %put &sysmacroname &newpath exists so grab the follow on link ;
    data _null_;
      set &libref1..links;
      if rel='createChild' then
        call symputx('href',quote(trim(href)),'l');
    run;
  %end;
  %else %if &SYS_PROCHTTP_STATUS_CODE=404 %then %do;
    %put &sysmacroname &newpath not found - creating it now;
    %local fname2;
    %let fname2=%mf_getuniquefileref();
    data _null_;
      length json $1000;
      json=cats("'"
        ,'{"name":'
        ,quote(trim(symget('subfolder')))
        ,',"description":'
        ,quote("&subfolder, created by &sysmacroname")
        ,',"type":"folder"}'
        ,"'"
      );
      call symputx('json',json,'l');
    run;

    proc http method='POST'
        in=&json
        out=&fname2
        url=%unquote(%superq(href));
        headers "Authorization"="Bearer &&&access_token_var"
                'Content-Type'='application/vnd.sas.content.folder+json'
                'Accept'='application/vnd.sas.content.folder+json';
    run;
    %put &=SYS_PROCHTTP_STATUS_CODE;
    %put &=SYS_PROCHTTP_STATUS_PHRASE;
    data _null_;infile &fname2;input;putlog _infile_;run;
    %mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 201)
      ,mac=&sysmacroname
      ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
    )
    %local libref2;
    %let libref2=%mf_getuniquelibref();
    libname &libref2 JSON fileref=&fname2;
    %put &sysmacroname &newpath now created. Grabbing the follow on link ;
    data _null_;
      set &libref2..links;
      if rel='createChild' then
        call symputx('href',quote(trim(href)),'l');
    run;

    libname &libref2 clear;
    filename &fname2 clear;
  %end;
  filename &fname1 clear;
  libname &libref1 clear;
%end;
%mend;/**
  @file mv_createwebservice.sas
  @brief Creates a JobExecution web service if it doesn't already exist
  @details  There are a number of steps involved in building a web service on
viya:

    %* Step 1 - load macros and obtain refresh token (must be ADMIN);
    filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
    %inc mc;
    %let client=new%sysfunc(ranuni(0),hex16.);
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
  @li mp_abort.sas
  @li mv_createfolder.sas
  @li mf_getuniquelibref.sas
  @li mf_getuniquefileref.sas
  @li mf_isblank.sas
  @li mv_deletejes.sas

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
  @param adapter= the macro uses the sasjs adapter by default.  To use another
    adapter, add a (different) fileref here.

  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

**/

%macro mv_createwebservice(path=
    ,name=
    ,desc=Created by the mv_createwebservice.sas macro
    ,precode=
    ,code=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=authorization_code
    ,replace=NO
    ,adapter=sasjs
  );
/* initial validation checking */
%mp_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%mf_isblank(&name)=1)
  ,mac=&sysmacroname
  ,msg=%str(name value must be provided)
)
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;

* remove any trailing slash ;
%if "%substr(&path,%length(&path),1)" = "/" %then
  %let path=%substr(&path,1,%length(&path)-1);

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
%mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200)
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
%mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200)
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
  %mp_abort(iftrue=(&exists=1)
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
filename sasjs temp lrecl=3000;
data _null_;
  file sasjs;
  put "/* Created on %sysfunc(datetime(),datetime19.) by &sysuserid */";
/* WEBOUT BEGIN */
  put '%macro mv_webout(action,ds,_webout=_webout,fref=_temp,dslabel=); ';
  put '%global _webin_file_count _webout_fileuri _debug _omittextlog ; ';
  put '%local i tempds; ';
  put '%let action=%upcase(&action); ';
  put ' ';
  put '%if &action=FETCH %then %do; ';
  put '  %if %upcase(&_omittextlog)=FALSE or &_debug ge 131 %then %do; ';
  put '    options mprint notes mprintnest; ';
  put '  %end; ';
  put ' ';
  put '  %if not %symexist(_webout_fileuri1) %then %do; ';
  put '    %let _webin_file_count=%eval(&_webin_file_count+0); ';
  put '    %let _webout_fileuri1=&_webout_fileuri; ';
  put '  %end; ';
  put ' ';
  put '  %if %symexist(sasjs_tables) %then %do; ';
  put '    /* small volumes of non-special data are sent as params for responsiveness */ ';
  put '    filename _sasjs "%sysfunc(pathname(work))/sasjs.lua"; ';
  put '    data _null_; ';
  put '      file _sasjs; ';
  put '      put ''s=sas.symget("sasjs_tables")''; ';
  put '      put ''if(s:sub(1,7) == "%nrstr(")''; ';
  put '      put ''then''; ';
  put '      put '' tablist=s:sub(8,s:len()-1)''; ';
  put '      put ''else''; ';
  put '      put '' tablist=s''; ';
  put '      put ''end''; ';
  put '      put ''for i = 1,sas.countw(tablist) ''; ';
  put '      put ''do ''; ';
  put '      put ''  tab=sas.scan(tablist,i)''; ';
  put '      put ''  sasdata=""''; ';
  put '      put ''  if (sas.symexist("sasjs"..i.."data0")==0)''; ';
  put '      put ''  then''; ';
  put '      /* TODO - condense this logic */ ';
  put '      put ''    s=sas.symget("sasjs"..i.."data")''; ';
  put '      put ''    if(s:sub(1,7) == "%nrstr(")''; ';
  put '      put ''    then''; ';
  put '      put ''      sasdata=s:sub(8,s:len()-1)''; ';
  put '      put ''    else''; ';
  put '      put ''      sasdata=s''; ';
  put '      put ''    end''; ';
  put '      put ''  else''; ';
  put '      put ''    for d = 1, sas.symget("sasjs"..i.."data0")''; ';
  put '      put ''    do''; ';
  put '      put ''      s=sas.symget("sasjs"..i.."data"..d)''; ';
  put '      put ''      if(s:sub(1,7) == "%nrstr(")''; ';
  put '      put ''      then''; ';
  put '      put ''        sasdata=sasdata..s:sub(8,s:len()-1)''; ';
  put '      put ''      else''; ';
  put '      put ''        sasdata=sasdata..s''; ';
  put '      put ''      end''; ';
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
  put '    %do i=1 %to %sysfunc(countw(&sasjs_tables)); ';
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
  put '  %else %do i=1 %to &_webin_file_count; ';
  put '    /* read in any files that are sent */ ';
  put '    filename indata filesrvc "&&_webout_fileuri&i" lrecl=999999; ';
  put '    data _null_; ';
  put '      infile indata termstr=crlf ; ';
  put '      input; ';
  put '      if _n_=1 then call symputx(''input_statement'',_infile_); ';
  put '      %if &_debug ge 131 %then %do; ';
  put '        if _n_<20 then putlog _infile_; ';
  put '        else stop; ';
  put '      %end; ';
  put '      %else %do; ';
  put '        stop; ';
  put '      %end; ';
  put '    run; ';
  put '    data &&_webin_name&i; ';
  put '      infile indata firstobs=2 dsd termstr=crlf ; ';
  put '      input &input_statement; ';
  put '    run; ';
  put '  %end; ';
  put ' ';
  put '%end; ';
  put ' ';
  put '%else %if &action=OPEN %then %do; ';
  put '  /* setup webout */ ';
  put '  filename &_webout filesrvc parenturi="&SYS_JES_JOB_URI" ';
  put '    name="_webout.json" lrecl=999999 mod; ';
  put ' ';
  put '  /* setup temp ref */ ';
  put '  %if %upcase(&fref) ne _WEBOUT %then %do; ';
  put '    filename &fref temp lrecl=999999 mod; ';
  put '  %end; ';
  put ' ';
  put '  /* setup json */ ';
  put '  data _null_;file &fref; ';
  put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"''; ';
  put '  run; ';
  put '%end; ';
  put '%else %if &action=ARR or &action=OBJ %then %do; ';
  put '  options validvarname=upcase; ';
  put '  data _null_;file &fref mod; ';
  put '    put ", ""%lowcase(%sysfunc(coalescec(&dslabel,&ds)))"":"; ';
  put '  data;run;%let tempds=&syslast; ';
  put '  proc sql;drop table &tempds; ';
  put '  data &tempds /view=&tempds;set &ds; format _numeric_ best32.; ';
  put '  proc json out=&fref ';
  put '      %if &action=ARR %then nokeys ; ';
  put '      %if &_debug ge 131  %then pretty ; ';
  put '    ;export &tempds / nosastags fmtnumeric; ';
  put '  run; ';
  put '  proc sql;drop view &tempds; ';
  put '%end; ';
  put '%else %if &action=CLOSE %then %do; ';
  put '  %if &_debug ge 131 %then %do; ';
  put '    /* send back first 10 records of each work table for debugging */ ';
  put '    options obs=10; ';
  put '    data;run;%let tempds=%scan(&syslast,2,.); ';
  put '    ods output Members=&tempds; ';
  put '    proc datasets library=WORK memtype=data; ';
  put '    %local wtcnt;%let wtcnt=0; ';
  put '    data _null_; set &tempds; ';
  put '      if not (name =:"DATA"); ';
  put '      i+1; ';
  put '      call symputx(''wt''!!left(i),name); ';
  put '      call symputx(''wtcnt'',i); ';
  put '    data _null_; file &fref; put ",""WORK"":{"; ';
  put '    %do i=1 %to &wtcnt; ';
  put '      %let wt=&&wt&i; ';
  put '      proc contents noprint data=&wt ';
  put '        out=&tempds (keep=name type length format:); ';
  put '      data _null_; file &fref; ';
  put '        dsid=open("WORK.&wt",''is''); ';
  put '        nlobs=attrn(dsid,''NLOBS''); ';
  put '        nvars=attrn(dsid,''NVARS''); ';
  put '        rc=close(dsid); ';
  put '        if &i>1 then put '',''@; ';
  put '        put " ""&wt"" : {"; ';
  put '        put ''"nlobs":'' nlobs; ';
  put '        put '',"nvars":'' nvars; ';
  put '      %mv_webout(OBJ,&wt,dslabel=first10rows) ';
  put '      %mv_webout(ARR,&tempds,dslabel=colattrs) ';
  put '      data _null_; file &fref;put "}"; ';
  put '    %end; ';
  put '    data _null_; file &fref;put "}";run; ';
  put '  %end; ';
  put ' ';
  put '  /* close off json */ ';
  put '  data _null_;file &fref mod; ';
  put '    _PROGRAM=quote(trim(resolve(symget(''_PROGRAM'')))); ';
  put '    put ",""SYSUSERID"" : ""&sysuserid"" "; ';
  put '    SYS_JES_JOB_URI=quote(trim(resolve(symget(''SYS_JES_JOB_URI'')))); ';
  put '    put '',"SYS_JES_JOB_URI" : '' SYS_JES_JOB_URI ; ';
  put '    put ",""SYSJOBID"" : ""&sysjobid"" "; ';
  put '    put '',"_PROGRAM" : '' _PROGRAM ; ';
  put '    put ",""SYSCC"" : ""&syscc"" "; ';
  put '    put ",""SYSERRORTEXT"" : ""&syserrortext"" "; ';
  put '    put ",""SYSJOBID"" : ""&sysjobid"" "; ';
  put '    put ",""SYSWARNINGTEXT"" : ""&syswarningtext"" "; ';
  put '    put '',"END_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''" ''; ';
  put '    put "}"; ';
  put ' ';
  put '  data _null_; rc=fcopy("&fref","&_webout");run; ';
  put ' ';
  put '%end; ';
  put ' ';
  put '%mend; ';
/* WEBOUT END */
  put '%macro webout(action,ds,_webout=_webout,fref=_temp);';
  put '  %mv_webout(&action,ds=&ds,_webout=&_webout,fref=&fref)';
  put '%mend;';
  put '%webout(FETCH)';
run;

/* insert the code, escaping double quotes and carriage returns */
%local x fref freflist;
%let freflist= &adapter &precode &code ;
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
/*data _null_;infile &fname4;input;putlog _infile_;run;*/
%mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 201)
  ,mac=&sysmacroname
  ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
)
/* clear refs */
filename &fname1 clear;
filename &fname2 clear;
filename &fname3 clear;
filename &fname4 clear;
filename &adapter clear;
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
/**
  @file mv_deletejes.sas
  @brief Creates a job execution service if it does not already exist
  @details Expects oauth token in a global macro variable (default
    ACCESS_TOKEN).

    filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
    %inc mc;
    %let client=new%sysfunc(ranuni(0));
    %let secret=MySecret;
    %mv_getapptoken(client_id=&client,client_secret=&secret)
    %mv_getrefreshtoken(client_id=&client,client_secret=&secret,code=wKDZYTEPK6)
    %mv_getaccesstoken(client_id=&client,client_secret=&secret)

    %mv_createwebservice(path=/Public/test, name=blah)
    %mv_deletejes(path=/Public/test, name=blah)


  @param path= The full path of the folder containing the Job Execution Service
  @param name= The name of the Job Execution Service to be deleted
  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas

**/

%macro mv_deletejes(path=
    ,name=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=authorization_code
  );

%mp_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%mf_isblank(&name)=1)
  ,mac=&sysmacroname
  ,msg=%str(name value must be provided)
)
%mp_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;

%put &sysmacroname: fetching details for &path ;
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1
  url="http://localhost/folders/folders/@item?path=&path";
  headers "Authorization"="Bearer &&&access_token_var";
run;
%if &SYS_PROCHTTP_STATUS_CODE=404 %then %do;
  %put &sysmacroname: Folder &path NOT FOUND - nothing to delete!;
  %return;
%end;
%else %if &SYS_PROCHTTP_STATUS_CODE ne 200 %then %do;
  /*data _null_;infile &fname1;input;putlog _infile_;run;*/
  %mp_abort(mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
%end;

%put &sysmacroname: grab the follow on link ;
%local libref1;
%let libref1=%mf_getuniquelibref();
libname &libref1 JSON fileref=&fname1;
data _null_;
  set &libref1..links;
  if rel='members' then call symputx('mref',quote(trim(href)),'l');
run;

/* get the children */
%local fname1a;
%let fname1a=%mf_getuniquefileref();
proc http method='GET' out=&fname1a
  url=%unquote(%superq(mref));
  headers "Authorization"="Bearer &&&access_token_var";
run;
%put &=SYS_PROCHTTP_STATUS_CODE;
%local libref1a;
%let libref1a=%mf_getuniquelibref();
libname &libref1a JSON fileref=&fname1a;
%local uri found;
%let found=0;
%put Getting object uri from &libref1a..items;
data _null_;
  set &libref1a..items;
  if contenttype='jobDefinition' and name="&name" then do;
    call symputx('uri',uri,'l');
    call symputx('found',1,'l');
  end;
run;
%if &found=0 %then %do;
  %put NOTE:;%put NOTE- &sysmacroname: &path/&name NOT FOUND;%put NOTE- ;
  %return;
%end;
proc http method="DELETE" url="&uri";
  headers "Authorization"="Bearer &&&access_token_var" "Accept"="*/*";/**/
run;
%if &SYS_PROCHTTP_STATUS_CODE ne 204 %then %do;
  data _null_; infile &fname2; input; putlog _infile_;run;
  %mp_abort(mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
%end;
%else %put &sysmacroname: &path/&name successfully deleted;

/* clear refs */
filename &fname1 clear;
libname &libref1 clear;
filename &fname1a clear;
libname &libref1a clear;

%mend;/**
  @file mv_deleteviyafolder.sas
  @brief Creates a viya folder if that foloder does not already exist
  @details Expects oauth token in a global macro variable (default
    ACCESS_TOKEN).

    options mprint;
    %mv_createfolder(path=/Public/test/blah)
    %mv_deleteviyafolder(path=/Public/test)


  @param path= The full path of the folder to be deleted
  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas

**/

%macro mv_deleteviyafolder(path=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=authorization_code
  );

%mp_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;

%put &sysmacroname: fetching details for &path ;
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1
  url="http://localhost/folders/folders/@item?path=&path";
  headers "Authorization"="Bearer &&&access_token_var";
run;
%if &SYS_PROCHTTP_STATUS_CODE=404 %then %do;
  %put &sysmacroname: Folder &path NOT FOUND - nothing to delete!;
  %return;
%end;
%else %if &SYS_PROCHTTP_STATUS_CODE ne 200 %then %do;
  /*data _null_;infile &fname1;input;putlog _infile_;run;*/
  %mp_abort(mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
%end;

%put &sysmacroname: grab the follow on link ;
%local libref1;
%let libref1=%mf_getuniquelibref();
libname &libref1 JSON fileref=&fname1;
data _null_;
  set &libref1..links;
  if rel='deleteRecursively' then
    call symputx('href',quote(trim(href)),'l');
  else if rel='members' then
    call symputx('mref',quote(cats(href,'?recursive=true')),'l');
run;

/* before we can delete the folder, we need to delete the children */
%local fname1a;
%let fname1a=%mf_getuniquefileref();
proc http method='GET' out=&fname1a
  url=%unquote(%superq(mref));
  headers "Authorization"="Bearer &&&access_token_var";
run;
%put &=SYS_PROCHTTP_STATUS_CODE;
%local libref1a;
%let libref1a=%mf_getuniquelibref();
libname &libref1a JSON fileref=&fname1a;

data _null_;
  set &libref1a..items_links;
  if href=:'/folders/folders' then return;
  if rel='deleteResource' then
    call execute('proc http method="DELETE" url='!!quote(trim(href))
    !!'; headers "Authorization"="Bearer &&&access_token_var" '
    !!' "Accept"="*/*";run; /**/');
run;

%put &sysmacroname: perform the delete operation ;
%local fname2;
%let fname2=%mf_getuniquefileref();
proc http method='DELETE'
    out=&fname2
    url=%unquote(%superq(href));
    headers "Authorization"="Bearer &&&access_token_var"
            'Accept'='*/*'; /**/
run;
%if &SYS_PROCHTTP_STATUS_CODE ne 204 %then %do;
  data _null_; infile &fname2; input; putlog _infile_;run;
  %mp_abort(mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
%end;
%else %put &sysmacroname: &path successfully deleted;

/* clear refs */
filename &fname1 clear;
filename &fname2 clear;
libname &libref1 clear;

%mend;/**
  @file
  @brief Get an additional access token using a refresh token
  @details Before an access token can be obtained, a refresh token is required
    For that, check out the `mv_getrefreshtoken` macro.

  Usage:

    * prep work - register client, get refresh token, save it for later use ;
    %let client=testin88gtss;
    %let secret=MySecret;
    %mv_getapptoken(client_id=&client,client_secret=&secret)
    %mv_getrefreshtoken(client_id=&client,client_secret=&secret,code=wKDZYTEPK6)
    data _null_;
    file "~/refresh.token";
    put "&refresh_token";
    run;

    * now do the things n stuff;
    data _null_;
      infile "~/refresh.token";
      input;
      call symputx('refresh_token',_infile_);
    run;
    %mv_getaccesstoken(client_id=&client
      ,client_secret=&secret
    )

    A great article for explaining all these steps is available here:

    https://blogs.sas.com/content/sgf/2019/01/25/authentication-to-sas-viya/

  @param client_id= The client name
  @param client_secret= client secret
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.
  @param user= If grant_type=password then provide the username here
  @param pass= If grant_type=password then provide the password here
  @param access_token_var= The global macro variable to contain the access token
  @param refresh_token_var= The global macro variable containing the refresh token

  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getuniquefileref.sas

**/

%macro mv_getaccesstoken(client_id=someclient
    ,client_secret=somesecret
    ,grant_type=authorization_code
    ,code=
    ,user=
    ,pass=
    ,access_token_var=ACCESS_TOKEN
    ,refresh_token_var=REFRESH_TOKEN
  );
%global &access_token_var &refresh_token_var;
options noquotelenmax;

%local fref1 libref;

/* test the validity of inputs */
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

%mp_abort(iftrue=(&grant_type=password and (%str(&user)=%str() or %str(&pass)=%str()))
  ,mac=&sysmacroname
  ,msg=%str(username / password required)
)

%mp_abort(iftrue=(%str(&client)=%str() or %str(&secret)=%str())
  ,mac=&sysmacroname
  ,msg=%str(client / secret must both be provided)
)


/**
 * Request access token
 */
%let fref1=%mf_getuniquefileref();
proc http method='POST'
  in="grant_type=refresh_token%nrstr(&)refresh_token=&&&refresh_token_var"
  out=&fref1
  url='localhost/SASLogon/oauth/token'
  WEBUSERNAME="&client_id"
  WEBPASSWORD="&client_secret"
  AUTH_BASIC;
  headers "Accept"="application/json"
          "Content-Type"="application/x-www-form-urlencoded";
run;
data _null_;infile &fref1;input;put _infile_;run;

/**
 * Extract access / refresh tokens
 */

%let libref=%mf_getuniquelibref();
libname &libref JSON fileref=&fref1;

/* extract the token */
data _null_;
  set &libref..root;
  call symputx("&access_token_var",access_token);
  call symputx("&refresh_token_var",refresh_token);
run;

%put NOTE:;
%put NOTE- &access_token_var=&&&access_token_var;
%put NOTE- ;
%put NOTE- &refresh_token_var=&&&refresh_token_var;
%put NOTE- ;
/*
libname &libref clear;
filename &fref1 clear;
filename &fref2 clear;
*/
%mend;/**
  @file
  @brief Get an App Token and Secret
  @details When building apps on SAS Viya, an app id and secret is required.
  This macro will obtain the Consul Token and use that to call the Web Service.

    more info: https://developer.sas.com/reference/auth/#register
    and: http://proc-x.com/2019/01/authentication-to-sas-viya-a-couple-of-approaches/

  The default viyaroot location is /opt/sas/viya/config

  M3 required due to proc http headers

  Usage:

    filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/macrocore.sas";
    %inc mc;

    %mv_getapptoken(client_id=client,client_secret=secret)

  @param client_id= The client name
  @param client_secret= client secret
  @param grant_type= valid values are "password" or "authorization_code" (unquoted)

  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_loc.sas

**/

%macro mv_getapptoken(client_id=someclient
    ,client_secret=somesecret
    ,grant_type=authorization_code
  );
%local consul_token fname1 fname2 fname3 libref access_token url;

%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
options noquotelenmax;
/* first, get consul token needed to get client id / secret */
data _null_;
  infile "%mf_loc(VIYACONFIG)/etc/SASSecurityCertificateFramework/tokens/consul/default/client.token";
  input token:$64.;
  call symputx('consul_token',token);
run;

/* request the client details */
%let fname1=%mf_getuniquefileref();
proc http method='POST' out=&fname1
    url='http://localhost/SASLogon/oauth/clients/consul?callback=false&serviceId=app';
    headers "X-Consul-Token"="&consul_token";
run;

%let libref=%mf_getuniquelibref();
libname &libref JSON fileref=&fname1;

/* extract the token */
data _null_;
  set &libref..root;
  call symputx('access_token',access_token);
run;
%put &=access_token;

/**
 * register the new client
 */
%let fname2=%mf_getuniquefileref();
data _null_;
  file &fname2;
  clientid=quote(trim(symget('client_id')));
  clientsecret=quote(trim(symget('client_secret')));
  granttype=quote(trim(symget('grant_type')));
  put '{"client_id":' clientid ',"client_secret":' clientsecret
    ',"scope":["openid","*"],"authorized_grant_types": [' granttype ',"refresh_token"],'
    '"redirect_uri": "urn:ietf:wg:oauth:2.0:oob"}';
run;
data _null_;
  infile &fname2;
  input;
  putlog _infile_;
run;

%let fname3=%mf_getuniquefileref();
proc http method='POST' in=&fname2 out=&fname3
    url='http://localhost/SASLogon/oauth/clients';
    headers "Content-Type"="application/json"
            "Authorization"="Bearer &access_token";
run;

/* show response */
data _null_;
  infile &fname3;
  input;
  putlog _infile_;
run;

/* prepare url */
%if &grant_type=authorization_code %then %do;
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
%end;

%put Please provide the following details to the developer:;
%put ;
%put CLIENT_ID=&client_id;
%put CLIENT_SECRET=&client_secret;
%put GRANT_TYPE=&grant_type;
%put;
%if &grant_type=authorization_code %then %do;
  %put NOTE: The developer must also register below and select 'openid' to get the grant code:;
  %put NOTE- ;
  %put NOTE- &url/SASLogon/oauth/authorize?client_id=&client_id%str(&)response_type=code;
  %put NOTE- ;
%end;

/* clear refs */
filename &fname1 clear;
filename &fname2 clear;
filename &fname3 clear;
libname &libref clear;

%mend;/**
  @file mv_getfoldermembers.sas
  @brief Gets a list of folders (and ids) for a given root
  @details Works for both root level and below, oauth or password. Default is
    oauth, and the token is expected in a global ACCESS_TOKEN variable.

    %mv_getfoldermembers(root=/Public)


  @param root= The path for which to return the list of folders
  @param outds= The output dataset to create (default is work.mv_getfolders)
  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas

**/

%macro mv_getfoldermembers(root=/
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=authorization_code
    ,outds=mv_getfolders
  );

%if %mf_isblank(&root)=1 %then %let root=/;

%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
options noquotelenmax;

/* request the client details */
%local fname1 libref1;
%let fname1=%mf_getuniquefileref();
%let libref1=%mf_getuniquelibref();

%if "&root"="/" %then %do;
  /* if root just list root folders */
  proc http method='GET' out=&fname1
      url='http://localhost/folders/rootFolders';
      headers "Authorization"="Bearer &&&access_token_var";
  run;
  libname &libref1 JSON fileref=&fname1;
  data &outds;
    set &libref1..items;
  run;
%end;
%else %do;
  /* first get parent folder id */
  proc http method='GET' out=&fname1
      url="http://localhost/folders/folders/@item?path=&root";
      headers "Authorization"="Bearer &&&access_token_var";
  run;
  data _null_;infile &fname1;input;putlog _infile_;run;
  libname &libref1 JSON fileref=&fname1;
  /* now get the followon link to list members */
  data _null_;
    set &libref1..links;
    if rel='members' then call symputx('href',quote(trim(href)),'l');
  run;
  %local fname2 libref2;
  %let fname2=%mf_getuniquefileref();
  %let libref2=%mf_getuniquelibref();
  proc http method='GET' out=&fname2
      url=%unquote(%superq(href));
      headers "Authorization"="Bearer &&&access_token_var";
  run;
  libname &libref2 JSON fileref=&fname2;
  data &outds;
    set &libref2..items;
  run;
  filename &fname2 clear;
  libname &libref2 clear;
%end;


/* clear refs */
filename &fname1 clear;
libname &libref1 clear;

%mend;/**
  @file mv_getgroups.sas
  @brief Creates a dataset with a list of viya groups
  @details First, be sure you have an access token (which requires an app token).

  Using the macros here:

    filename mc url
      "https://raw.githubusercontent.com/macropeople/macrocore/master/macrocore.sas";
    %inc mc;

  An administrator needs to set you up with an access code:

    %let client=someclient;
    %let secret=MySecret;
    %mv_getapptoken(client_id=&client,client_secret=&secret)

  Navigate to the url from the log (opting in to the groups) and paste the
  access code below:

    %mv_getrefreshtoken(client_id=&client,client_secret=&secret,code=wKDZYTEPK6)
    %mv_getaccesstoken(client_id=&client,client_secret=&secret)

  Now we can run the macro!

    %mv_getgroups()

  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.
  @param outds= The library.dataset to be created that contains the list of groups


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas

**/

%macro mv_getgroups(access_token_var=ACCESS_TOKEN
    ,grant_type=authorization_code
    ,outds=work.viyagroups
  );
/* initial validation checking */
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;

/* fetching folder details for provided path */
%local fname1;
%let fname1=%mf_getuniquefileref();
%let libref1=%mf_getuniquelibref();

proc http method='GET' out=&fname1
  url="http://localhost/identities/groups";
  headers "Authorization"="Bearer &&&access_token_var"
          "Accept"="application/json";
run;
/*data _null_;infile &fname1;input;putlog _infile_;run;*/
%mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200)
  ,mac=&sysmacroname
  ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
)
libname &libref1 JSON fileref=&fname1;

data &outds;
  set &libref1..items;
run;



/* clear refs */
filename &fname1 clear;
libname &libref1 clear;

%mend;/**
  @file mv_getrefreshtoken.sas
  @brief Get Refresh Token (and initial access token)
  @details Before a Refresh Token can be obtained, the client must be
    registered by an administrator.  This can be done using the
    `mv_getapptoken` macro, after which the user must visit a URL to get an
    additional code (if using oauth).

    That code (or username / password) is used here to get the Refresh Token
    (and an initial Access Token).  THIS MACRO CAN ONLY BE USED ONCE - further
    access tokens can be obtained using the `mv_getaccesstoken` macro.

    Access tokens expire frequently (every 10 hours or so) whilst refresh tokens
    expire periodically (every month or so).  This is all configurable.

  Usage:

    filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/macrocore.sas";
    %inc mc;

    %let client=testings;
    %let secret=MySecret;

    %mv_getapptoken(client_id=&client,client_secret=&secret)

    %mv_getrefreshtoken(client_id=&client,client_secret=&secret,code=LD39EpalOf)

    A great article for explaining all these steps is available here:

    https://blogs.sas.com/content/sgf/2019/01/25/authentication-to-sas-viya/

  @param client_id= The client name
  @param client_secret= client secret
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.
  @param code= If grant_type=authorization_code then provide the necessary code here
  @param user= If grant_type=password then provide the username here
  @param pass= If grant_type=password then provide the password here
  @param access_token_var= The global macro variable to contain the access token
  @param refresh_token_var= The global macro variable to contain the refresh token

  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getuniquefileref.sas

**/

%macro mv_getrefreshtoken(client_id=someclient
    ,client_secret=somesecret
    ,grant_type=authorization_code
    ,code=
    ,user=
    ,pass=
    ,access_token_var=ACCESS_TOKEN
    ,refresh_token_var=REFRESH_TOKEN
  );
%global &access_token_var &refresh_token_var;

%local fref1 fref2 libref;

/* test the validity of inputs */
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password)
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

%mp_abort(iftrue=(&grant_type=authorization_code and %str(&code)=%str())
  ,mac=&sysmacroname
  ,msg=%str(Authorization code required)
)

%mp_abort(iftrue=(&grant_type=password and (%str(&user)=%str() or %str(&pass)=%str()))
  ,mac=&sysmacroname
  ,msg=%str(username / password required)
)

%mp_abort(iftrue=(%str(&client)=%str() or %str(&secret)=%str())
  ,mac=&sysmacroname
  ,msg=%str(client / secret must both be provided)
)

/* prepare appropriate grant type */
%let fref1=%mf_getuniquefileref();

data _null_;
  file &fref1;
  if "&grant_type"='authorization_code' then string=cats(
   'grant_type=authorization_code&code=',symget('code'));
  else string=cats('grant_type=password&username=',symget('user')
    ,'&password=',symget(pass));
  call symputx('grantstring',cats("'",string,"'"));
run;
data _null_;infile &fref1;input;put _infile_;run;

/**
 * Request access token
 */
%let fref2=%mf_getuniquefileref();
proc http method='POST' in=&grantstring out=&fref2
  url='localhost/SASLogon/oauth/token'
  WEBUSERNAME="&client_id"
  WEBPASSWORD="&client_secret"
  AUTH_BASIC;
  headers "Accept"="application/json"
          "Content-Type"="application/x-www-form-urlencoded";
run;
data _null_;infile &fref2;input;put _infile_;run;

/**
 * Extract access / refresh tokens
 */

%let libref=%mf_getuniquelibref();
libname &libref JSON fileref=&fref2;

/* extract the token */
data _null_;
  set &libref..root;
  call symputx("&access_token_var",access_token);
  call symputx("&refresh_token_var",refresh_token);
run;

%put NOTE:;
%put NOTE- &access_token_var=&&&access_token_var;
%put NOTE- ;
%put NOTE- &refresh_token_var=&&&refresh_token_var;
%put NOTE- ;

libname &libref clear;
filename &fref1 clear;
filename &fref2 clear;

%mend;/**
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
  @param dslabel= value to use instead of the real name for sending to JSON

  @version Viya 3.3
  @author Allan Bowe

**/
%macro mv_webout(action,ds,_webout=_webout,fref=_temp,dslabel=);
%global _webin_file_count _webout_fileuri _debug _omittextlog ;
%local i tempds;
%let action=%upcase(&action);

%if &action=FETCH %then %do;
  %if %upcase(&_omittextlog)=FALSE or &_debug ge 131 %then %do;
    options mprint notes mprintnest;
  %end;

  %if not %symexist(_webout_fileuri1) %then %do;
    %let _webin_file_count=%eval(&_webin_file_count+0);
    %let _webout_fileuri1=&_webout_fileuri;
  %end;

  %if %symexist(sasjs_tables) %then %do;
    /* small volumes of non-special data are sent as params for responsiveness */
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
      /* TODO - condense this logic */
      put '    s=sas.symget("sasjs"..i.."data")';
      put '    if(s:sub(1,7) == "%nrstr(")';
      put '    then';
      put '      sasdata=s:sub(8,s:len()-1)';
      put '    else';
      put '      sasdata=s';
      put '    end';
      put '  else';
      put '    for d = 1, sas.symget("sasjs"..i.."data0")';
      put '    do';
      put '      s=sas.symget("sasjs"..i.."data"..d)';
      put '      if(s:sub(1,7) == "%nrstr(")';
      put '      then';
      put '        sasdata=sasdata..s:sub(8,s:len()-1)';
      put '      else';
      put '        sasdata=sasdata..s';
      put '      end';
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
    %do i=1 %to %sysfunc(countw(&sasjs_tables));
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
  %else %do i=1 %to &_webin_file_count;
    /* read in any files that are sent */
    filename indata filesrvc "&&_webout_fileuri&i" lrecl=999999;
    data _null_;
      infile indata termstr=crlf ;
      input;
      if _n_=1 then call symputx('input_statement',_infile_);
      %if &_debug ge 131 %then %do;
        if _n_<20 then putlog _infile_;
        else stop;
      %end;
      %else %do;
        stop;
      %end;
    run;
    data &&_webin_name&i;
      infile indata firstobs=2 dsd termstr=crlf ;
      input &input_statement;
    run;
  %end;

%end;

%else %if &action=OPEN %then %do;
  /* setup webout */
  filename &_webout filesrvc parenturi="&SYS_JES_JOB_URI"
    name="_webout.json" lrecl=999999 mod;

  /* setup temp ref */
  %if %upcase(&fref) ne _WEBOUT %then %do;
    filename &fref temp lrecl=999999 mod;
  %end;

  /* setup json */
  data _null_;file &fref;
    put '{"START_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '"';
  run;
%end;
%else %if &action=ARR or &action=OBJ %then %do;
  options validvarname=upcase;
  data _null_;file &fref mod;
    put ", ""%lowcase(%sysfunc(coalescec(&dslabel,&ds)))"":";
  data;run;%let tempds=&syslast;
  proc sql;drop table &tempds;
  data &tempds /view=&tempds;set &ds; format _numeric_ best32.;
  proc json out=&fref
      %if &action=ARR %then nokeys ;
      %if &_debug ge 131  %then pretty ;
    ;export &tempds / nosastags fmtnumeric;
  run;
  proc sql;drop view &tempds;
%end;
%else %if &action=CLOSE %then %do;
  %if &_debug ge 131 %then %do;
    /* send back first 10 records of each work table for debugging */
    options obs=10;
    data;run;%let tempds=%scan(&syslast,2,.);
    ods output Members=&tempds;
    proc datasets library=WORK memtype=data;
    %local wtcnt;%let wtcnt=0;
    data _null_; set &tempds;
      if not (name =:"DATA");
      i+1;
      call symputx('wt'!!left(i),name);
      call symputx('wtcnt',i);
    data _null_; file &fref; put ",""WORK"":{";
    %do i=1 %to &wtcnt;
      %let wt=&&wt&i;
      proc contents noprint data=&wt
        out=&tempds (keep=name type length format:);
      data _null_; file &fref;
        dsid=open("WORK.&wt",'is');
        nlobs=attrn(dsid,'NLOBS');
        nvars=attrn(dsid,'NVARS');
        rc=close(dsid);
        if &i>1 then put ','@;
        put " ""&wt"" : {";
        put '"nlobs":' nlobs;
        put ',"nvars":' nvars;
      %mv_webout(OBJ,&wt,dslabel=first10rows)
      %mv_webout(ARR,&tempds,dslabel=colattrs)
      data _null_; file &fref;put "}";
    %end;
    data _null_; file &fref;put "}";run;
  %end;

  /* close off json */
  data _null_;file &fref mod;
    _PROGRAM=quote(trim(resolve(symget('_PROGRAM'))));
    put ",""SYSUSERID"" : ""&sysuserid"" ";
    SYS_JES_JOB_URI=quote(trim(resolve(symget('SYS_JES_JOB_URI'))));
    put ',"SYS_JES_JOB_URI" : ' SYS_JES_JOB_URI ;
    put ",""SYSJOBID"" : ""&sysjobid"" ";
    put ',"_PROGRAM" : ' _PROGRAM ;
    put ",""SYSCC"" : ""&syscc"" ";
    put ",""SYSERRORTEXT"" : ""&syserrortext"" ";
    put ",""SYSJOBID"" : ""&sysjobid"" ";
    put ",""SYSWARNINGTEXT"" : ""&syswarningtext"" ";
    put ',"END_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '" ';
    put "}";

  data _null_; rc=fcopy("&fref","&_webout");run;

%end;

%mend;
