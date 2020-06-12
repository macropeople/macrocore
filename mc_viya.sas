/**
  @file mv_createfolder.sas
  @brief Creates a viya folder if that folder does not already exist
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
  @li mf_getplatform.sas

**/

%macro mv_createfolder(path=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;

%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

%mp_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)

options noquotelenmax;

%local subfolder_cnt; /* determine the number of subfolders */
%let subfolder_cnt=%sysfunc(countw(&path,/));

%local href; /* resource address (none for root) */
%let href="/folders/folders?parentFolderUri=/folders/folders/none";

%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

%local x newpath subfolder;
%do x=1 %to &subfolder_cnt;
  %let subfolder=%scan(&path,&x,%str(/));
  %let newpath=&newpath/&subfolder;

  %local fname1;
  %let fname1=%mf_getuniquefileref();

  %put &sysmacroname checking to see if &newpath exists;
  proc http method='GET' out=&fname1 &oauth_bearer
      url="&base_uri/folders/folders/@item?path=&newpath";
  %if &grant_type=authorization_code %then %do;
      headers "Authorization"="Bearer &&&access_token_var";
  %end;
  run;
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
        &oauth_bearer
        url=%unquote(%superq(href));
        headers 
      %if &grant_type=authorization_code %then %do;
                "Authorization"="Bearer &&&access_token_var"
      %end;
                'Content-Type'='application/vnd.sas.content.folder+json'
                'Accept'='application/vnd.sas.content.folder+json';
    run;
    %put &=SYS_PROCHTTP_STATUS_CODE;
    %put &=SYS_PROCHTTP_STATUS_PHRASE;
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

    %* Step 2 - Create some code and add it to a web service;
    filename ft15f001 temp;
    parmcards4;
        %webout(FETCH) %* fetch any tables sent from frontend;
        %* do some sas, any inputs are now already WORK tables;
        data example1 example2;
          set sashelp.class;
        run;
        %* send data back;
        %webout(OPEN)
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
  @li mf_getplatform.sas
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
  @param replace= select NO to avoid replacing any existing service in that location
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
    ,code=ft15f001
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
    ,replace=YES
    ,adapter=sasjs
    ,debug=0
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;

/* initial validation checking */
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
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

options noquotelenmax;

* remove any trailing slash ;
%if "%substr(&path,%length(&path),1)" = "/" %then
  %let path=%substr(&path,1,%length(&path)-1);

/* ensure folder exists */
%put &sysmacroname: Path &path being checked / created;
%mv_createfolder(path=&path)

%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

/* fetching folder details for provided path */
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/folders/folders/@item?path=&path";
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var";
%end;
run;
%if &debug %then %do;
  data _null_;
    infile &fname1;
    input;
    putlog _infile_;
  run;
%end;
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
    &oauth_bearer
    url=%unquote(%superq(membercheck));
    headers
  %if &grant_type=authorization_code %then %do;
            "Authorization"="Bearer &&&access_token_var"
  %end;
            'Accept'='application/vnd.sas.collection+json'
            'Accept-Language'='string';
%if &debug=1 %then %do;
   debug level = 3;
%end;
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
  put ' ';
  put '%macro mp_jsonout(action,ds,jref=_webout,dslabel=,fmt=Y,engine=PROCJSON,dbg=0 ';
  put ')/*/STORE SOURCE*/; ';
  put '%put output location=&jref; ';
  put '%if &action=OPEN %then %do; ';
  put '  data _null_;file &jref encoding=''utf-8''; ';
  put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"''; ';
  put '  run; ';
  put '%end; ';
  put '%else %if (&action=ARR or &action=OBJ) %then %do; ';
  put '  options validvarname=upcase; ';
  put '  data _null_;file &jref mod encoding=''utf-8''; ';
  put '    put ", ""%lowcase(%sysfunc(coalescec(&dslabel,&ds)))"":"; ';
  put ' ';
  put '  %if &engine=PROCJSON %then %do; ';
  put '    data;run;%let tempds=&syslast; ';
  put '    proc sql;drop table &tempds; ';
  put '    data &tempds /view=&tempds;set &ds; ';
  put '    %if &fmt=N %then format _numeric_ best32.;; ';
  put '    proc json out=&jref ';
  put '        %if &action=ARR %then nokeys ; ';
  put '        %if &dbg ge 131  %then pretty ; ';
  put '        ;export &tempds / nosastags fmtnumeric; ';
  put '    run; ';
  put '    proc sql;drop view &tempds; ';
  put '  %end; ';
  put '  %else %if &engine=DATASTEP %then %do; ';
  put '    %local cols i tempds; ';
  put '    %let cols=0; ';
  put '    %if %sysfunc(exist(&ds)) ne 1 & %sysfunc(exist(&ds,VIEW)) ne 1 %then %do; ';
  put '      %put &sysmacroname:  &ds NOT FOUND!!!; ';
  put '      %return; ';
  put '    %end; ';
  put '    data _null_;file &jref mod ; ';
  put '      put "["; call symputx(''cols'',0,''l''); ';
  put '    proc sort data=sashelp.vcolumn(where=(libname=''WORK'' & memname="%upcase(&ds)")) ';
  put '      out=_data_; ';
  put '      by varnum; ';
  put ' ';
  put '    data _null_; ';
  put '      set _last_ end=last; ';
  put '      call symputx(cats(''name'',_n_),name,''l''); ';
  put '      call symputx(cats(''type'',_n_),type,''l''); ';
  put '      call symputx(cats(''len'',_n_),length,''l''); ';
  put '      if last then call symputx(''cols'',_n_,''l''); ';
  put '    run; ';
  put ' ';
  put '    proc format; /* credit yabwon for special null removal */ ';
  put '      value bart ._ - .z = null ';
  put '      other = [best.]; ';
  put ' ';
  put '    data;run; %let tempds=&syslast; /* temp table for spesh char management */ ';
  put '    proc sql; drop table &tempds; ';
  put '    data &tempds/view=&tempds; ';
  put '      attrib _all_ label=''''; ';
  put '      %do i=1 %to &cols; ';
  put '        %if &&type&i=char %then %do; ';
  put '          length &&name&i $32767; ';
  put '          format &&name&i $32767.; ';
  put '        %end; ';
  put '      %end; ';
  put '      set &ds; ';
  put '      format _numeric_ bart.; ';
  put '    %do i=1 %to &cols; ';
  put '      %if &&type&i=char %then %do; ';
  put '        &&name&i=''"''!!trim(prxchange(''s/"/\"/'',-1, ';
  put '                    prxchange(''s/''!!''0A''x!!''/\n/'',-1, ';
  put '                    prxchange(''s/''!!''0D''x!!''/\r/'',-1, ';
  put '                    prxchange(''s/''!!''09''x!!''/\t/'',-1, ';
  put '                    prxchange(''s/\\/\\\\/'',-1,&&name&i) ';
  put '        )))))!!''"''; ';
  put '      %end; ';
  put '    %end; ';
  put '    run; ';
  put '    /* write to temp loc to avoid _webout truncation - https://support.sas.com/kb/49/325.html */ ';
  put '    filename _sjs temp lrecl=131068 encoding=''utf-8''; ';
  put '    data _null_; file _sjs lrecl=131068 encoding=''utf-8'' mod; ';
  put '      set &tempds; ';
  put '      if _n_>1 then put "," @; put ';
  put '      %if &action=ARR %then "[" ; %else "{" ; ';
  put '      %do i=1 %to &cols; ';
  put '        %if &i>1 %then  "," ; ';
  put '        %if &action=OBJ %then """&&name&i"":" ; ';
  put '        &&name&i ';
  put '      %end; ';
  put '      %if &action=ARR %then "]" ; %else "}" ; ; ';
  put '    proc sql; ';
  put '    drop view &tempds; ';
  put '    /* now write the long strings to _webout 1 byte at a time */ ';
  put '    data _null_; ';
  put '      length filein 8 fileid 8; ';
  put '      filein = fopen("_sjs",''I'',1,''B''); ';
  put '      fileid = fopen("&jref",''A'',1,''B''); ';
  put '      rec = ''20''x; ';
  put '      do while(fread(filein)=0); ';
  put '        rc = fget(filein,rec,1); ';
  put '        rc = fput(fileid, rec); ';
  put '        rc =fwrite(fileid); ';
  put '      end; ';
  put '      rc = fclose(filein); ';
  put '      rc = fclose(fileid); ';
  put '    run; ';
  put '    filename _sjs clear; ';
  put '    data _null_; file &jref mod encoding=''utf-8''; ';
  put '      put "]"; ';
  put '    run; ';
  put '  %end; ';
  put '%end; ';
  put ' ';
  put '%else %if &action=CLOSE %then %do; ';
  put '  data _null_;file &jref encoding=''utf-8''; ';
  put '    put "}"; ';
  put '  run; ';
  put '%end; ';
  put '%mend; ';
  put '%macro mv_webout(action,ds,fref=_mvwtemp,dslabel=,fmt=Y); ';
  put '%global _webin_file_count _webout_fileuri _debug _omittextlog ; ';
  put '%if %index("&_debug",log) %then %let _debug=131; ';
  put ' ';
  put '%local i tempds; ';
  put '%let action=%upcase(&action); ';
  put ' ';
  put '%if &action=FETCH %then %do; ';
  put '  %if %upcase(&_omittextlog)=FALSE or %str(&_debug) ge 131 %then %do; ';
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
  put '    /* to do - deal with escaped values  */ ';
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
  put '      %if %str(&_debug) ge 131 %then %do; ';
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
  put '%end; ';
  put '%else %if &action=OPEN %then %do; ';
  put '  /* setup webout */ ';
  put '  OPTIONS NOBOMFILE; ';
  put '  filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" ';
  put '    name="_webout.json" lrecl=999999 mod; ';
  put ' ';
  put '  /* setup temp ref */ ';
  put '  %if %upcase(&fref) ne _WEBOUT %then %do; ';
  put '    filename &fref temp lrecl=999999 permission=''A::u::rwx,A::g::rw-,A::o::---'' mod; ';
  put '  %end; ';
  put ' ';
  put '  /* setup json */ ';
  put '  data _null_;file &fref; ';
  put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"''; ';
  put '  run; ';
  put '%end; ';
  put '%else %if &action=ARR or &action=OBJ %then %do; ';
  put '    %mp_jsonout(&action,&ds,dslabel=&dslabel,fmt=&fmt ';
  put '      ,jref=&fref,engine=PROCJSON,dbg=%str(&_debug) ';
  put '    ) ';
  put '%end; ';
  put '%else %if &action=CLOSE %then %do; ';
  put '  %if %str(&_debug) ge 131 %then %do; ';
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
  put '        out=_data_ (keep=name type length format:); ';
  put '      run;%let tempds=%scan(&syslast,2,.); ';
  put '      data _null_; file &fref; ';
  put '        dsid=open("WORK.&wt",''is''); ';
  put '        nlobs=attrn(dsid,''NLOBS''); ';
  put '        nvars=attrn(dsid,''NVARS''); ';
  put '        rc=close(dsid); ';
  put '        if &i>1 then put '',''@; ';
  put '        put " ""&wt"" : {"; ';
  put '        put ''"nlobs":'' nlobs; ';
  put '        put '',"nvars":'' nvars; ';
  put '      %mp_jsonout(OBJ,&tempds,jref=&fref,dslabel=colattrs,engine=DATASTEP) ';
  put '      %mp_jsonout(OBJ,&wt,jref=&fref,dslabel=first10rows,engine=DATASTEP) ';
  put '      data _null_; file &fref;put "}"; ';
  put '    %end; ';
  put '    data _null_; file &fref;put "}";run; ';
  put '  %end; ';
  put ' ';
  put '  /* close off json */ ';
  put '  data _null_;file &fref mod; ';
  put '    _PROGRAM=quote(trim(resolve(symget(''_PROGRAM'')))); ';
  put '    put ",""SYSUSERID"" : ""&sysuserid"" "; ';
  put '    put ",""MF_GETUSER"" : ""%mf_getuser()"" "; ';
  put '    SYS_JES_JOB_URI=quote(trim(resolve(symget(''SYS_JES_JOB_URI'')))); ';
  put '    put '',"SYS_JES_JOB_URI" : '' SYS_JES_JOB_URI ; ';
  put '    put ",""SYSJOBID"" : ""&sysjobid"" "; ';
  put '    put ",""_DEBUG"" : ""&_debug"" "; ';
  put '    put '',"_PROGRAM" : '' _PROGRAM ; ';
  put '    put ",""SYSCC"" : ""&syscc"" "; ';
  put '    put ",""SYSERRORTEXT"" : ""&syserrortext"" "; ';
  put '    put ",""SYSHOSTNAME"" : ""&syshostname"" "; ';
  put '    put ",""SYSSITE"" : ""&syssite"" "; ';
  put '    put ",""SYSWARNINGTEXT"" : ""&syswarningtext"" "; ';
  put '    put '',"END_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''" ''; ';
  put '    put "}"; ';
  put ' ';
  put '  %if %upcase(&fref) ne _WEBOUT %then %do; ';
  put '    data _null_; rc=fcopy("&fref","_webout");run; ';
  put '  %end; ';
  put ' ';
  put '%end; ';
  put ' ';
  put '%mend; ';
  put ' ';
  put '%macro mf_getuser(type=META ';
  put ')/*/STORE SOURCE*/; ';
  put '  %local user metavar; ';
  put '  %if &type=OS %then %let metavar=_secureusername; ';
  put '  %else %let metavar=_metaperson; ';
  put ' ';
  put '  %if %symexist(SYS_COMPUTE_SESSION_OWNER) %then %let user=&SYS_COMPUTE_SESSION_OWNER; ';
  put '  %else %if %symexist(&metavar) %then %do; ';
  put '    %if %length(&&&metavar)=0 %then %let user=&sysuserid; ';
  put '    /* sometimes SAS will add @domain extension - remove for consistency */ ';
  put '    %else %let user=%scan(&&&metavar,1,@); ';
  put '  %end; ';
  put '  %else %let user=&sysuserid; ';
  put ' ';
  put '  %quote(&user) ';
  put ' ';
  put '%mend; ';
/* WEBOUT END */
  put '%macro webout(action,ds,dslabel=,fmt=);';
  put '  %mv_webout(&action,ds=&ds,dslabel=&dslabel,fmt=&fmt)';
  put '%mend;';
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
    &oauth_bearer
    url="/jobDefinitions/definitions?parentFolderUri=&parentFolderUri";
    headers 'Content-Type'='application/vnd.sas.job.definition+json'
  %if &grant_type=authorization_code %then %do;
            "Authorization"="Bearer &&&access_token_var"
  %end;
            "Accept"="application/vnd.sas.job.definition+json";
%if &debug=1 %then %do;
   debug level = 3;
%end;
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


%put &sysmacroname: Job &name successfully created in &path;
%put &sysmacroname:;
%put &sysmacroname: Check it out here:;
%put &sysmacroname:;%put;
%put    &url/SASJobExecution?_PROGRAM=&path/&name;%put;
%put &sysmacroname:;
%put &sysmacroname:;

%mend;
/**
  @file mv_deletefoldermember.sas
  @brief Deletes an item in a Viya folder
  @details If not executed in Studio 5+  will expect oauth token in a global 
  macro variable (default ACCESS_TOKEN).

      filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
      %inc mc;

      %mv_createwebservice(path=/Public/test, name=blah)
      %mv_deletejes(path=/Public/test, name=blah)


  @param path= The full path of the folder containing the item to be deleted
  @param name= The name of the item to be deleted
  @param contenttype= The contenttype of the item, eg: file, jobDefinition
  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is "detect" (which will run in Studio 5+ without a token).


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas

**/

%macro mv_deletefoldermember(path=
    ,name=
    ,contenttype=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
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

options noquotelenmax;

%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

%put &sysmacroname: fetching details for &path ;
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/folders/folders/@item?path=&path";
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var";
%end;
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
proc http method='GET' out=&fname1a &oauth_bearer
  url=%unquote(%superq(mref));
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var";
%end;
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
  if contenttype="&contenttype" and upcase(name)="%upcase(&name)" then do;
    call symputx('uri',uri,'l');
    call symputx('found',1,'l');
  end;
run;
%if &found=0 %then %do;
  %put NOTE:;%put NOTE- &sysmacroname: &path/&name NOT FOUND;%put NOTE- ;
  %return;
%end;
proc http method="DELETE" url="&uri" &oauth_bearer;
  headers 
%if &grant_type=authorization_code %then %do;
      "Authorization"="Bearer &&&access_token_var"
%end;
      "Accept"="*/*";/**/
run;
%if &SYS_PROCHTTP_STATUS_CODE ne 204 %then %do;
  data _null_; infile &fname2; input; putlog _infile_;run;
  %mp_abort(mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
%end;
%else %put &sysmacroname: &path/&name(&contenttype) successfully deleted;

/* clear refs */
filename &fname1 clear;
libname &libref1 clear;
filename &fname1a clear;
libname &libref1a clear;

%mend;/**
  @file mv_deletejes.sas
  @brief Creates a job execution service if it does not already exist
  @details If not executed in Studio 5+  will expect oauth token in a global 
  macro variable (default ACCESS_TOKEN).

      filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
      %inc mc;

      %mv_createwebservice(path=/Public/test, name=blah)
      %mv_deletejes(path=/Public/test, name=blah)


  @param path= The full path of the folder containing the Job Execution Service
  @param name= The name of the Job Execution Service to be deleted
  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is "detect" (which will run in Studio 5+ without a token).


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas

**/

%macro mv_deletejes(path=
    ,name=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
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

options noquotelenmax;
%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

%put &sysmacroname: fetching details for &path ;
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/folders/folders/@item?path=&path";
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var";
%end;
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
proc http method='GET' out=&fname1a &oauth_bearer
  url=%unquote(%superq(mref));
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var";
%end;
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
  if contenttype='jobDefinition' and upcase(name)="%upcase(&name)" then do;
    call symputx('uri',uri,'l');
    call symputx('found',1,'l');
  end;
run;
%if &found=0 %then %do;
  %put NOTE:;%put NOTE- &sysmacroname: &path/&name NOT FOUND;%put NOTE- ;
  %return;
%end;
proc http method="DELETE" url="&uri" &oauth_bearer;
  headers 
%if &grant_type=authorization_code %then %do;
      "Authorization"="Bearer &&&access_token_var"
%end;
      "Accept"="*/*";/**/
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
  @brief Creates a viya folder if that folder does not already exist
  @details If not running in Studo 5 +, will expect an oauth token in a global 
  macro variable (default ACCESS_TOKEN).

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
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas

**/

%macro mv_deleteviyafolder(path=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
%mp_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)

options noquotelenmax;
%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

%put &sysmacroname: fetching details for &path ;
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/folders/folders/@item?path=&path";
  %if &grant_type=authorization_code %then %do;
    headers "Authorization"="Bearer &&&access_token_var";
  %end;
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
proc http method='GET' out=&fname1a &oauth_bearer
  url=%unquote(%superq(mref));
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var";
%end;
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
proc http method='DELETE' out=&fname2 &oauth_bearer
    url=%unquote(%superq(href));
    headers 
  %if &grant_type=authorization_code %then %do;
            "Authorization"="Bearer &&&access_token_var"
  %end;   
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

%mend; /**
   @file mv_getaccesstoken.sas
   @brief deprecated - replaced by mv_tokenrefresh.sas

   @version VIYA V.03.04
   @author Allan Bowe
   @source https://github.com/macropeople/macrocore
 
   <h4> Dependencies </h4>
   @li mv_tokenrefresh.sas

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

%mv_tokenrefresh(client_id=&client_id
  ,client_secret=&client_secret
  ,grant_type=&grant_type
  ,user=&user
  ,pass=&pass
  ,access_token_var=&access_token_var
  ,refresh_token_var=&refresh_token_var
)

%mend; /**
   @file
   @brief deprecated - replaced by mv_registerclient.sas

   @version VIYA V.03.04
   @author Allan Bowe
   @source https://github.com/macropeople/macrocore
 
   <h4> Dependencies </h4>
   @li mv_registerclient.sas

 **/
 
 %macro mv_getapptoken(client_id=someclient
     ,client_secret=somesecret
     ,grant_type=authorization_code
   );

%mv_registerclient(client_id=&client_id
  ,client_secret=&client_secret
  ,grant_type=&grant_type
)

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
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_isblank.sas

**/

%macro mv_getfoldermembers(root=/
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
    ,outds=mv_getfolders
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

%if %mf_isblank(&root)=1 %then %let root=/;

options noquotelenmax;

/* request the client details */
%local fname1 libref1;
%let fname1=%mf_getuniquefileref();
%let libref1=%mf_getuniquelibref();

%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

%if "&root"="/" %then %do;
  /* if root just list root folders */
  proc http method='GET' out=&fname1 &oauth_bearer
      url='%sysfunc(getoption(servicesbaseurl))/folders/rootFolders';
  %if &grant_type=authorization_code %then %do;
      headers "Authorization"="Bearer &&&access_token_var";
  %end;
  run;
  libname &libref1 JSON fileref=&fname1;
  data &outds;
    set &libref1..items;
  run;
%end;
%else %do;
  /* first get parent folder id */
  proc http method='GET' out=&fname1 &oauth_bearer
      url="&base_uri/folders/folders/@item?path=&root";
  %if &grant_type=authorization_code %then %do;
      headers "Authorization"="Bearer &&&access_token_var";
  %end;
  run;
  /*data _null_;infile &fname1;input;putlog _infile_;run;*/
  libname &libref1 JSON fileref=&fname1;
  /* now get the followon link to list members */
  data _null_;
    set &libref1..links;
    if rel='members' then call symputx('href',quote(trim(href)),'l');
  run;
  %local fname2 libref2;
  %let fname2=%mf_getuniquefileref();
  %let libref2=%mf_getuniquelibref();
  proc http method='GET' out=&fname2 &oauth_bearer
      url=%unquote(%superq(href));
  %if &grant_type=authorization_code %then %do;
      headers "Authorization"="Bearer &&&access_token_var";
  %end;
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
  @file mv_getgroupmembers.sas
  @brief Creates a dataset with a list of group members
  @details First, be sure you have an access token (which requires an app token).

  Using the macros here:

      filename mc url
        "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
      %inc mc;

  Now we can run the macro!

      %mv_getgroupmembers(All Users)

  outputs:

      ordinal_root num,
      ordinal_items num,
      version num,
      id char(43),
      name char(43),
      providerId char(5),
      implicit num

  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.
  @param outds= The library.dataset to be created that contains the list of groups


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas

**/

%macro mv_getgroupmembers(group
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
    ,outds=work.viyagroupmembers
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;

%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

/* fetching folder details for provided path */
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/identities/groups/&group/members?limit=1000";
  headers 
  %if &grant_type=authorization_code %then %do;
          "Authorization"="Bearer &&&access_token_var"
  %end;
          "Accept"="application/json";
run;
/*data _null_;infile &fname1;input;putlog _infile_;run;*/
%if &SYS_PROCHTTP_STATUS_CODE=404 %then %do;
  %put NOTE:  Group &group not found!!;
  data &outds;
    length id name $43;
    call missing(of _all_);
  run;
%end;
%else %do;
  %mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200)
    ,mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
  %let libref1=%mf_getuniquelibref();
  libname &libref1 JSON fileref=&fname1;
  data &outds;
    length id name $43;
    set &libref1..items;
  run;
  libname &libref1 clear;
%end;

/* clear refs */
filename &fname1 clear;

%mend;/**
  @file mv_getgroups.sas
  @brief Creates a dataset with a list of viya groups
  @details First, be sure you have an access token (which requires an app token).

  Using the macros here:

      filename mc url
        "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
      %inc mc;

  An administrator needs to set you up with an access code:

      %mv_registerclient(outds=client)

  Navigate to the url from the log (opting in to the groups) and paste the
  access code below:

      %mv_tokenauth(inds=client,code=wKDZYTEPK6)

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
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas

**/

%macro mv_getgroups(access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
    ,outds=work.viyagroups
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;
%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

/* fetching folder details for provided path */
%local fname1;
%let fname1=%mf_getuniquefileref();
%let libref1=%mf_getuniquelibref();

proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/identities/groups";
  headers 
  %if &grant_type=authorization_code %then %do;
          "Authorization"="Bearer &&&access_token_var"
  %end;
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

%mend; /**
   @file mv_getrefreshtoken.sas
   @brief deprecated - replaced by mv_tokenauth.sas

   @version VIYA V.03.04
   @author Allan Bowe
   @source https://github.com/macropeople/macrocore
 
   <h4> Dependencies </h4>
   @li mv_tokenauth.sas

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

%mv_tokenauth(client_id=&client_id
  ,client_secret=&client_secret
  ,grant_type=&grant_type
  ,code=&code
  ,user=&user
  ,pass=&pass
  ,access_token_var=&access_token_var
  ,refresh_token_var=&refresh_token_var
)

%mend;/**
  @file mv_getusergroups.sas
  @brief Creates a dataset with a list of groups for a particular user
  @details First, be sure you have an access token (which requires an app token).

  Using the macros here:

      filename mc url
        "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
      %inc mc;

  An administrator needs to set you up with an access code:

      %mv_registerclient(outds=client)

  Navigate to the url from the log (opting in to the groups) and paste the
  access code below:

      %mv_tokenauth(inds=client,code=wKDZYTEPK6)

  Now we can run the macro!

      %mv_getusergroups(&sysuserid,outds=users)

  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values are "password" or "authorization_code" (unquoted).
    The default is authorization_code.
  @param outds= The library.dataset to be created that contains the list of groups


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas

**/

%macro mv_getusergroups(user
    ,outds=work.mv_getusergroups
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
options noquotelenmax;

%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

/* fetching folder details for provided path */
%local fname1;
%let fname1=%mf_getuniquefileref();
%let libref1=%mf_getuniquelibref();

proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/identities/users/&user/memberships?limit=2000";
  headers 
%if &grant_type=authorization_code %then %do;
         "Authorization"="Bearer &&&access_token_var"
%end;
          "Accept"="application/json";
run;
/*data _null_;infile &fname1;input;putlog _infile_;run;*/
%if &SYS_PROCHTTP_STATUS_CODE=404 %then %do;
  %put NOTE:  User &user not found!!;
%end;
%else %do;
  %mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200)
    ,mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
%end;
libname &libref1 JSON fileref=&fname1;

data &outds;
  set &libref1..items;
run;

/* clear refs */
filename &fname1 clear;
libname &libref1 clear;

%mend;/**
  @file mv_getusers.sas
  @brief Creates a dataset with a list of users
  @details First, be sure you have an access token (which requires an app token).

  Using the macros here:

      filename mc url
      "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
      %inc mc;

  An administrator needs to set you up with an access code:

      %mv_registerclient(outds=client)

  Navigate to the url from the log (opting in to the groups) and paste the
  access code below:

      %mv_tokenauth(inds=client,code=wKDZYTEPK6)

  Now we can run the macro!

      %mv_getusers(outds=users)

  Output (lengths are dynamic):

      ordinal_root num,
      ordinal_items num,
      version num,
      id char(20),
      name char(23),
      providerId char(4),
      type char(4),
      creationTimeStamp char(24),
      modifiedTimeStamp char(24),
      state char(6)
 
  @param access_token_var= The global macro variable to contain the access token
  @param grant_type= valid values:
   * password
   * authorization_code
   * detect - will check if access_token exists, if not will use sas_services if 
    a SASStudioV session else authorization_code.  Default option.
   * sas_services - will use oauth_bearer=sas_services

  @param outds= The library.dataset to be created that contains the list of groups


  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas

**/

%macro mv_getusers(outds=work.mv_getusers
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;

%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

/* fetching folder details for provided path */
%local fname1;
%let fname1=%mf_getuniquefileref();
%let libref1=%mf_getuniquelibref();

proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/identities/users?limit=2000";
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var"
          "Accept"="application/json";
%end;
%else %do;
  headers "Accept"="application/json";
%end;
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
  @file mv_registerclient.sas
  @brief Register Client and Secret (admin task)
  @details When building apps on SAS Viya, an client id and secret is required.
  This macro will obtain the Consul Token and use that to call the Web Service.

    more info: https://developer.sas.com/reference/auth/#register
    and: http://proc-x.com/2019/01/authentication-to-sas-viya-a-couple-of-approaches/

  The default viyaroot location is /opt/sas/viya/config

  M3 required due to proc http headers

  Usage:

      %* compile macros;
      filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
      %inc mc;

      %* specific client with just openid scope;
      %mv_registerclient(client_id=YourClient
        ,client_secret=YourSecret
        ,scopes=openid
      )

      %* generate random client details with all scopes;
      %mv_registerclient(scopes=openid *)

      %* generate random client with 90/180 second access/refresh token expiry;
      %mv_registerclient(scopes=openid *
        ,access_token_validity=90
        ,refresh_token_validity=180
      )

  @param client_id= The client name.  Auto generated if blank.
  @param client_secret= Client secret  Auto generated if client is blank.
  @param scopes= list of space-seperated unquoted scopes (default is openid)
  @param grant_type= valid values are "password" or "authorization_code" (unquoted)
  @param outds= the dataset to contain the registered client id and secret
  @param access_token_validity= The duration of validity of the access token 
    in seconds.  A value of DEFAULT will omit the entry (and use system default)
  @param refresh_token_validity= The duration of validity of the refresh token
    in seconds.  A value of DEFAULT will omit the entry (and use system default)
    
  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_loc.sas
  @li mf_getquotedstr.sas

**/

%macro mv_registerclient(client_id=
    ,client_secret=
    ,scopes=
    ,grant_type=authorization_code
    ,outds=mv_registerclient
    ,access_token_validity=DEFAULT
    ,refresh_token_validity=DEFAULT
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

%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

/* request the client details */
%let fname1=%mf_getuniquefileref();
proc http method='POST' out=&fname1
    url="&base_uri/SASLogon/oauth/clients/consul?callback=false%str(&)serviceId=app";
    headers "X-Consul-Token"="&consul_token";
run;

%let libref=%mf_getuniquelibref();
libname &libref JSON fileref=&fname1;

/* extract the token */
data _null_;
  set &libref..root;
  call symputx('access_token',access_token,'l');
run;

/**
 * register the new client
 */
%let fname2=%mf_getuniquefileref();
%if x&client_id.x=xx %then %do;
  %let client_id=client_%sysfunc(ranuni(0),hex16.);
  %let client_secret=secret_%sysfunc(ranuni(0),hex16.);
%end;
%local scope;
%let scopes=%sysfunc(coalescec(&scopes,openid));
%let scope=%mf_getquotedstr(&scopes,QUOTE=D);
data _null_;
  file &fname2;
  clientid=quote(trim(symget('client_id')));
  clientsecret=quote(trim(symget('client_secret')));
  scope=symget('scope');
  granttype=quote(trim(symget('grant_type')));
  put '{"client_id":' clientid ',"client_secret":' clientsecret
%if &access_token_validity ne DEFAULT %then %do;
    ',"access_token_validity":' "&access_token_validity"
%end;
%if &refresh_token_validity ne DEFAULT %then %do;
    ',"refresh_token_validity":' "&refresh_token_validity"
%end;
    ',"scope":[' scope '],"authorized_grant_types": [' granttype ',"refresh_token"],'
    '"redirect_uri": "urn:ietf:wg:oauth:2.0:oob"}';
run;

%let fname3=%mf_getuniquefileref();
proc http method='POST' in=&fname2 out=&fname3
    url="&base_uri/SASLogon/oauth/clients";
    headers "Content-Type"="application/json"
            "Authorization"="Bearer &access_token";
run;

/* show response */
%let err=NONE;
data _null_;
  infile &fname3;
  input;
  if _infile_=:'{"err'!!'or":' then do;
    length message $32767;
    message=scan(_infile_,-2,'"');
    call symputx('err',message,'l');
  end;
run;
%if &err ne NONE %then %do;
  %put %str(ERR)OR: &err;
  %return;
%end;

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
  /* cannot use base_uri here as it includes the protocol which may be incorrect externally */
  %put NOTE: The developer must also register below and select 'openid' to get the grant code:;
  %put NOTE- ;
  %put NOTE- &url/SASLogon/oauth/authorize?client_id=&client_id%str(&)response_type=code;
  %put NOTE- ;
%end;

data &outds;
  client_id=symget('client_id');
  client_secret=symget('client_secret');
run;

/* clear refs */
filename &fname1 clear;
filename &fname2 clear;
filename &fname3 clear;
libname &libref clear;

%mend;
/**
  @file mv_tokenauth.sas
  @brief Get initial Refresh and Access Tokens
  @details Before a Refresh Token can be obtained, the client must be
    registered by an administrator.  This can be done using the
    `mv_registerclient` macro, after which the user must visit a URL to get an
    additional code (if using oauth).

    That code (or username / password) is used here to get the Refresh Token
    (and an initial Access Token).  THIS MACRO CAN ONLY BE USED ONCE - further
    access tokens can be obtained using the `mv_gettokenrefresh` macro.

    Access tokens expire frequently (every 10 hours or so) whilst refresh tokens
    expire periodically (every month or so).  This is all configurable.

  Usage:

      filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
      %inc mc;


      %mv_registerclient(outds=clientinfo)

      %mv_tokenauth(inds=clientinfo,code=LD39EpalOf)

    A great article for explaining all these steps is available here:

    https://blogs.sas.com/content/sgf/2019/01/25/authentication-to-sas-viya/

  @param inds= A dataset containing client_id, client_secret, and auth_code
  @param outds= A dataset containing access_token and refresh_token
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
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_existds.sas

**/

%macro mv_tokenauth(inds=mv_registerclient
    ,outds=mv_tokenauth
    ,client_id=someclient
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

%if %mf_existds(&inds) %then %do;
  data _null_;
    set &inds;
    call symputx('client_id',client_id,'l');
    call symputx('client_secret',client_secret,'l');
    if not missing(auth_code) then call symputx('code',auth_code,'l');
  run;
%end;

%mp_abort(iftrue=(&grant_type=authorization_code and %str(&code)=%str())
  ,mac=&sysmacroname
  ,msg=%str(Authorization code required)
)

%mp_abort(iftrue=(&grant_type=password and (%str(&user)=%str() or %str(&pass)=%str()))
  ,mac=&sysmacroname
  ,msg=%str(username / password required)
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
/*data _null_;infile &fref1;input;put _infile_;run;*/

/**
 * Request access token
 */
%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

%let fref2=%mf_getuniquefileref();
proc http method='POST' in=&grantstring out=&fref2
  url="&base_uri/SASLogon/oauth/token"
  WEBUSERNAME="&client_id"
  WEBPASSWORD="&client_secret"
  AUTH_BASIC;
  headers "Accept"="application/json"
          "Content-Type"="application/x-www-form-urlencoded";
run;
/*data _null_;infile &fref2;input;put _infile_;run;*/

/**
 * Extract access / refresh tokens
 */

%let libref=%mf_getuniquelibref();
libname &libref JSON fileref=&fref2;

/* extract the tokens */
data &outds;
  set &libref..root;
  call symputx("&access_token_var",access_token);
  call symputx("&refresh_token_var",refresh_token);
run;


libname &libref clear;
filename &fref1 clear;
filename &fref2 clear;

%mend;/**
  @file mv_tokenrefresh.sas
  @brief Get an additional access token using a refresh token
  @details Before an access token can be obtained, a refresh token is required
    For that, check out the `mv_tokenauth` macro.

  Usage:

      * prep work - register client, get refresh token, save it for later use ;
      %mv_registerclient(outds=client)
      %mv_tokenauth(inds=client,code=wKDZYTEPK6)
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
      %mv_tokenrefresh(client_id=&client
        ,client_secret=&secret
      )

  A great article for explaining all these steps is available here:

  https://blogs.sas.com/content/sgf/2019/01/25/authentication-to-sas-viya/

  @param inds= A dataset containing client_id and client_secret
  @param outds= A dataset containing access_token and refresh_token
  @param client_id= The client name (alternative to inds)
  @param client_secret= client secret (alternative to inds)
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
  @li mf_getplatform.sas
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_existds.sas

**/

%macro mv_tokenrefresh(inds=mv_registerclient
    ,outds=mv_tokenrefresh
    ,client_id=someclient
    ,client_secret=somesecret
    ,grant_type=authorization_code
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

%if %mf_existds(&inds) %then %do;
  data _null_;
    set &inds;
    call symputx('client_id',client_id,'l');
    call symputx('client_secret',client_secret,'l');
    call symputx("&refresh_token_var",&refresh_token_var,'l');
  run;
%end;

%mp_abort(iftrue=(%str(&client_id)=%str() or %str(&client_secret)=%str())
  ,mac=&sysmacroname
  ,msg=%str(client / secret must both be provided)
)

/**
 * Request access token
 */
%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);

%let fref1=%mf_getuniquefileref();
proc http method='POST'
  in="grant_type=refresh_token%nrstr(&)refresh_token=&&&refresh_token_var"
  out=&fref1
  url="&base_uri/SASLogon/oauth/token"
  WEBUSERNAME="&client_id"
  WEBPASSWORD="&client_secret"
  AUTH_BASIC;
  headers "Accept"="application/json"
          "Content-Type"="application/x-www-form-urlencoded";
run;
/*data _null_;infile &fref1;input;put _infile_;run;*/

/**
 * Extract access / refresh tokens
 */

%let libref=%mf_getuniquelibref();
libname &libref JSON fileref=&fref1;

/* extract the token */
data &outds;
  set &libref..root;
  call symputx("&access_token_var",access_token);
  call symputx("&refresh_token_var",refresh_token);
run;


libname &libref clear;
filename &fref1 clear;

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
  @param fmt= change to N to strip formats from output

  <h4> Dependencies </h4>
  @li mp_jsonout.sas
  @li mf_getuser.sas

  @version Viya 3.3
  @author Allan Bowe

**/
%macro mv_webout(action,ds,fref=_mvwtemp,dslabel=,fmt=Y);
%global _webin_file_count _webout_fileuri _debug _omittextlog ;
%if %index("&_debug",log) %then %let _debug=131; 

%local i tempds;
%let action=%upcase(&action);

%if &action=FETCH %then %do;
  %if %upcase(&_omittextlog)=FALSE or %str(&_debug) ge 131 %then %do;
    options mprint notes mprintnest;
  %end;

  %if not %symexist(_webout_fileuri1) %then %do;
    %let _webin_file_count=%eval(&_webin_file_count+0);
    %let _webout_fileuri1=&_webout_fileuri;
  %end;

  %if %symexist(sasjs_tables) %then %do;
    /* small volumes of non-special data are sent as params for responsiveness */
    /* to do - deal with escaped values  */
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
      %if %str(&_debug) ge 131 %then %do;
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
  OPTIONS NOBOMFILE;
  filename _webout filesrvc parenturi="&SYS_JES_JOB_URI"
    name="_webout.json" lrecl=999999 mod;

  /* setup temp ref */
  %if %upcase(&fref) ne _WEBOUT %then %do;
    filename &fref temp lrecl=999999 permission='A::u::rwx,A::g::rw-,A::o::---' mod;
  %end;

  /* setup json */
  data _null_;file &fref;
    put '{"START_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '"';
  run;
%end;
%else %if &action=ARR or &action=OBJ %then %do;
    %mp_jsonout(&action,&ds,dslabel=&dslabel,fmt=&fmt
      ,jref=&fref,engine=PROCJSON,dbg=%str(&_debug)
    )
%end;
%else %if &action=CLOSE %then %do;
  %if %str(&_debug) ge 131 %then %do;
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
        out=_data_ (keep=name type length format:);
      run;%let tempds=%scan(&syslast,2,.);
      data _null_; file &fref;
        dsid=open("WORK.&wt",'is');
        nlobs=attrn(dsid,'NLOBS');
        nvars=attrn(dsid,'NVARS');
        rc=close(dsid);
        if &i>1 then put ','@;
        put " ""&wt"" : {";
        put '"nlobs":' nlobs;
        put ',"nvars":' nvars;
      %mp_jsonout(OBJ,&tempds,jref=&fref,dslabel=colattrs,engine=DATASTEP)
      %mp_jsonout(OBJ,&wt,jref=&fref,dslabel=first10rows,engine=DATASTEP)
      data _null_; file &fref;put "}";
    %end;
    data _null_; file &fref;put "}";run;
  %end;

  /* close off json */
  data _null_;file &fref mod;
    _PROGRAM=quote(trim(resolve(symget('_PROGRAM'))));
    put ",""SYSUSERID"" : ""&sysuserid"" ";
    put ",""MF_GETUSER"" : ""%mf_getuser()"" ";
    SYS_JES_JOB_URI=quote(trim(resolve(symget('SYS_JES_JOB_URI'))));
    put ',"SYS_JES_JOB_URI" : ' SYS_JES_JOB_URI ;
    put ",""SYSJOBID"" : ""&sysjobid"" ";
    put ",""_DEBUG"" : ""&_debug"" ";
    put ',"_PROGRAM" : ' _PROGRAM ;
    put ",""SYSCC"" : ""&syscc"" ";
    put ",""SYSERRORTEXT"" : ""&syserrortext"" ";
    put ",""SYSHOSTNAME"" : ""&syshostname"" ";
    put ",""SYSSITE"" : ""&syssite"" ";
    put ",""SYSWARNINGTEXT"" : ""&syswarningtext"" ";
    put ',"END_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '" ';
    put "}";

  %if %upcase(&fref) ne _WEBOUT %then %do;
    data _null_; rc=fcopy("&fref","_webout");run;
  %end;

%end;

%mend;
