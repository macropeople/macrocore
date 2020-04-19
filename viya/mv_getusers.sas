/**
  @file mv_getusers.sas
  @brief Creates a dataset with a list of users
  @details First, be sure you have an access token (which requires an app token).

  Using the macros here:

      filename mc url
      "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
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
  @li mf_getuniquefileref.sas
  @li mf_getuniquelibref.sas
  @li mf_getplatform.sas

**/

%macro mv_getusers(outds=work.mv_getusers
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=detect
  );
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %if %mf_getplatform(SASSTUDIO) ge 5 %then %do;
    %let grant_type=sas_services;
    %let &access_token_var=;
  %end;
  %else %let grant_type=password;
%end;
%put &=grant_type;

/* initial validation checking */
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password 
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)

options noquotelenmax;

/* fetching folder details for provided path */
%local fname1;
%let fname1=%mf_getuniquefileref();
%let libref1=%mf_getuniquelibref();

proc http method='GET' out=&fname1
%if &grant_type=sas_services %then %do;
  oauth_bearer=sas_services
%end;
  url="http://localhost/identities/users?limit=2000";
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

%mend;