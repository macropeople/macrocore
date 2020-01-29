/**
  @file mp_cleancsv.sas
  @brief Fixes embedded cr / lf / crlf in CSV
  @details CSVs will sometimes contain lf or crlf within quotes (eg when
    saved by excel).  When the termstr is ALSO lf or crlf that can be tricky
    to process using SAS defaults.
    This macro converts any csv to follow the convention of a windows excel file,
    applying CRLF line endings and converting embedded cr and crlf to lf.

  usage:

      mp_cleancsv(inloc=/path/your.csv,outloc=/path/new.csv)

  @param inloc= input csv
  @param outloc= output csv
  @param qchar= quote char - hex code 22 is the double quote.

  @version 9.2
  @author Allan Bowe
**/

%macro mp_cleancsv(inloc=,outloc=,qchar='22'x);
/**
 * convert all cr and crlf within quotes to lf
 * convert all other cr or lf to crlf
 */
  data _null_;
    infile "&inloc" recfm=n ;
    file "&outloc" recfm=n;
    retain isq iscrlf 0 qchar &qchar;
    input inchar $char1. ;
    if inchar=qchar then isq = mod(isq+1,2);
    if isq then do;
      /* inside a quote change cr and crlf to lf */
      if inchar='0D'x then do;
        put '0A'x;
        input inchar $char1.;
        if inchar ne '0A'x then do;
          put inchar $char1.;
          if inchar=qchar then isq = mod(isq+1,2);
        end;
      end;
      else put inchar $char1.;
    end;
    else do;
      /* outside a quote, change cr and lf to crlf */
      if inchar='0D'x then do;
        put '0D0A'x;
        input inchar $char1.;
        if inchar ne '0A'x then do;
          put inchar $char1.;
          if inchar=qchar then isq = mod(isq+(inchar=qchar),2);
        end;
      end;
      else if inchar='0A'x then put '0D0A'x;
      else put inchar $char1.;
    end;
  run;
%mend;