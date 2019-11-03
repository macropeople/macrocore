/**
  @file mp_searchcols.sas
  @brief Searches all columns in a library
  @details
  Scans an entire library and creates a dataset containing all the source tables
    that contain one or more of a particular set of columns

  Usage:

      %mp_searchcols(lib=sashelp, cols=name sex age)

  @version 9.2
  @author Allan Bowe
**/

%macro mp_searchcols(lib=sashelp
  ,cols=
  ,outds=mp_searchcols
)/*/STORE SOURCE*/;

%put &sysmacroname process began at %sysfunc(datetime(),datetime19.);

/* get the list of tables in the library */
proc sql;
create table _data_ as
  select distinct upcase(libname) as libname
    , upcase(memname) as memname
    , upcase(name) as name
  from dictionary.columns where upcase(libname)="%upcase(&lib)"
  order by 1,2,3;

data &outds;
  set &syslast;
  length cols matchcols $32767;
  cols=upcase(symget('cols'));
  colcount=countw(cols);
  by libname memname name;
  if first.memname then do;
    sumcols=0;
    retain matchcols;
    matchcols='';
  end;
  if findw(cols,name,,'spit') then do;
    sumcols+1;
    matchcols=cats(matchcols)!!' '!!cats(name);
  end;
  if last.memname then do;
    if sumcols>0 then output;
    if sumcols=colcount then putlog "Full Match: " libname memname;
  end;
  keep libname memname sumcols matchcols;
run;

proc sort; by descending sumcols memname libname; run;

%put &sysmacroname process finished at %sysfunc(datetime(),datetime19.);

%mend;
