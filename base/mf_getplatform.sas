/**
  @file mf_getplatform
  @brief Returns platform specific variables
  @details Enables platform specific variables to be returned

      %put %mf_getplatform()

    returns:
      SASMETA  (or SASVIYA)

  @param switch the param for which to return a platform specific variable

  @version 9.4 / 3.4
  @author Allan Bowe
**/

%macro mf_getplatform(
     switch=NONE
)/*/STORE SOURCE*/;
%let switch=%upcase(&switch);
%if &switch=NONE %then %do;
  %if %symexist(sysprocessmode) %then %do;
    %if "&sysprocessmode"="SAS Object Server" %then %do;
        SASVIYA
    %end;
    %else %if "&sysprocessmode"="SAS Stored Process Server" %then %do;
      SASMETA
      %return;
    %end;
    %else %do;
      SAS
      %return;
    %end;
  %end;
  %else %if %symexist(_metaport) %then %do;
    SASMETA
    %return;
  %end;
  %else %do;
    SAS
    %return;
  %end;
%end;
%mend;