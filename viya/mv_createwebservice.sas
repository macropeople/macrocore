/**
  @file mv_createwebservice.sas
  @brief Creates a JobExecution object if it doesn't already exist
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
      proc sql;
      create table myds as
        select * from sashelp.class;
      %sasjs(myds)
      ;;;;
    %mv_createwebservice(path=/Public/myapp, name=testJob, code=temp)


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
 * Create setup code
 * This uses LUA to process JSON received as a series of macro variables
 */
%local setup;
%let setup=%mf_getuniquefileref();
data _null_;
  file &setup;
  put '%global sasjs0 sasjs1;';
  put '/*' / ' example json:';
  put '%let sasjs0=1;';
  put '%let sasjs1={"data": {"SOMETABLE": [
			["COL1", "COL2", "COL3"],
			[1, 2, "3/**/"],
			[2, 3, "4"]
		],
		"ANOTHERTABLE": [
			["COL4", "COL5", "COL6"],
			[1, 2, "3"],
			[2, 3, "4"]
		]
	},"url":"somelocal.url/for/info"};';
  put '*/';
  put '%let work=%sysfunc(pathname(work));';
  put '/* create lua file for reading JSON */';
  put 'filename ft15f001 "&work/json2sas.lua";';
  put 'parmcards4;';
run;

/* get lua file and write it to the stp under the parmcards statement */
%ml_json2sas()
data _null_;
  file &setup;
  infile "%sysfunc(pathname(work))/json2sas.lua" end=last;
  input;
  put _infile_;
  if last then do;
    put ';;;;';
    put 'filename luapath "&work"; ';
    put "proc lua infile='json2sas';";
    put '  submit;';
    put '  local json2sas=require("json2sas")';
    put '  rc=json2sas.go("sasjs")';
    put 'endsubmit;';
    put 'run;';
  end;
run;

/**
 * Create output macro
 */
data _null_;
  file &setup;
  put '/* setup json */';
  put 'filename _web temp lrecl=65000;';
  put 'data _null_;file _web;put "{data:{";run;'/;
  put '/* output macro */';
  put '%macro sasjs(dsn);';
  put 'options validvarname=upcase;';
  put 'data _null_;file _web mod;';
  put ' put ''"'' "&dsn" ''" : '';run;';
  put 'proc json out=_web mod;export work.&dsn / nosastags;run;';
  put 'data _null_;file _web mod;put ",";run;';
  put '%mend;' //;
run;

/* now insert the teardown / wrapup code */
%local teardown;
%let teardown=%mf_getuniquefileref();
data _null_;
  file &teardown;
  put '/* close off json */';
  put 'data _null_;file _web mod;';
  put "  SYS_JES_JOB_URI=quote(trim(resolve(symget('SYS_JES_JOB_URI'))));";
  put '  jobid=quote(scan(SYS_JES_JOB_URI,-2,''/"''));';
  put "  _PROGRAM=quote(trim(resolve(symget('_PROGRAM'))));";
  put '  put ''"sysuserid" : "'' "&sysuserid." ''",'';';
  put '  put ''"sysjobid" : "'' "&sysjobid." ''",'';';
  put '  put ''"sysjobid" : "'' "&sysjobid." ''",'';';
  put '  put ''"datetime" : "'' "%sysfunc(datetime(),datetime19.)" ''",'';';
  put '  put ''"SYS_JES_JOB_URI" : '' SYS_JES_JOB_URI '','';';
  put '  put ''"X-SAS-JOBEXEC-ID" : '' jobid '','';';
  put '  put ''"_PROGRAM" : '' _PROGRAM '','';';
  put '  put "}";';
  put 'run;';
  put ' ';
  put '/* send to _webout */';
  put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name="_webout.json";';
  put "data _null_;rc=fcopy('_web','_webout');run;";
run;


/* insert the code, escaping double quotes and carriage returns */
%local x fref freflist;
%let freflist= &setup &precode &code &teardown;
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

/* finish off the body */
data _null_;
  file &fname3 mod TERMSTR=' ';
  /*
  put '\rfilename _web filesrvc parenturi=\"&SYS_JES_JOB_URI\" name=\"_webout.json\";' @@;
  put '\r%let rc=%sysfunc(fcopy(_webout,_web));' @@;
  */
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

%put &sysmacroname: Job &name successfully created in &path;

%mend;