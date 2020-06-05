/**
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

      %* specific client with just openid scope
      %mv_registerclient(client_id=YourClient
        ,client_secret=YourSecret
        ,scopes=openid
      )

      %* generate random client details with all scopes
      %mv_registerclient(scopes=openid *)

  @param client_id= The client name.  Auto generated if blank.
  @param client_secret= Client secret  Auto generated if client is blank.
  @param scopes= list of space-seperated unquoted scopes (default is openid)
  @param grant_type= valid values are "password" or "authorization_code" (unquoted)
  @param outds= the dataset to contain the registered client id and secret

  @version VIYA V.03.04
  @author Allan Bowe
  @source https://github.com/macropeople/macrocore

  <h4> Dependencies </h4>
  @li mp_abort.sas
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
    ',"scope":[' scope '],"authorized_grant_types": [' granttype ',"refresh_token"],'
    '"redirect_uri": "urn:ietf:wg:oauth:2.0:oob"}';
run;

%let fname3=%mf_getuniquefileref();
proc http method='POST' in=&fname2 out=&fname3
    url='http://localhost/SASLogon/oauth/clients';
    headers "Content-Type"="application/json"
            "Authorization"="Bearer &access_token";
run;

/* show response */
%let err=NONE;
data _null_;
  infile &fname3;
  input;
  if _infile_=:'{"err'!!'or":' then do;
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
