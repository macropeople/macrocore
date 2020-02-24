/**
  @file
  @brief Assigns a meta engine library using LIBREF
  @details Queries metadata to get the library NAME which can then be used in
    a libname statement with the meta engine.

  usage:

      %mm_assign_lib(SOMEREF);

  <h4> Dependencies </h4>
  @li mf_abort.sas

  @param libref the libref (not name) of the metadata library
  @param mDebug= set to 1 to show debug messages in the log
  @param mAbort= If not assigned, HARD will call %mf_abort(), SOFT will silently return

  @returns libname statement

  @version 9.2
  @author Allan Bowe

**/

%macro mm_assignlib(
     libref
    ,mDebug=0
    ,mAbort=HARD
)/*/STORE SOURCE*/;

%if %sysfunc(libref(&libref)) %then %do;
  %local mf_abort msg; %let mf_abort=0;
  data _null_;
    length liburi LibName $200;
    call missing(of _all_);
    nobj=metadata_getnobj("omsobj:SASLibrary?@Libref='&libref'",1,liburi);
    if nobj=1 then do;
       rc=metadata_getattr(liburi,"Name",LibName);
       put (_all_)(=);
       call symputx('libname',libname,'L');
       call symputx('liburi',liburi,'L');
    end;
    else if nobj>1 then do;
      if "&mabort"='HARD' then call symputx('mf_abort',1);
      call symputx('msg',"More than one library with libref=&libref");
    end;
    else do;
      if "&mabort"='HARD' then call symputx('mf_abort',1);
      call symputx('msg',"Library &libref not found in metadata");
    end;
  run;
  %if &mf_abort=1 %then %do;
    %mf_abort(iftrue= (&mf_abort=1)
      ,mac=mm_assignlib.sas
      ,msg=&msg
    )
    %return;
  %end;
  %else %if %length(&msg)>2 %then %do;
    %put NOTE: &msg;
    %return;
  %end;

  libname &libref meta liburi="&liburi";

  %if %sysfunc(libref(&libref)) and &mabort=HARD %then %do;
    %mf_abort(msg=mm_assignlib macro could not assign &libref (&libname)
      ,mac=mm_assignlib.sas)
    %return;
  %end;
%end;
%else %do;
  %put NOTE: Library &libref is already assigned;
%end;
%mend;