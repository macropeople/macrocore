/**
  @file mp_updatevarlength.sas
  @brief Change the length of a variable
  @details The library is assumed to be assigned.  Simple character updates
  currently supported, numerics are more complicated and will follow.

        data example;
          a='1';
          b='12';
          c='123';
        run;
        %mp_updatevarlength(example,a,3)
        %mp_updatevarlength(example,c,1)
        proc sql;
        describe table example;

  @param libds the library.dataset to be modified
  @param var The variable to modify
  @param len The new length to apply

  <h4> Dependencies </h4>
  @li mf_existds.sas
  @li mp_abort.sas
  @li mf_existvar.sas
  @li mf_getvarlen.sas
  @li mf_getvartype.sas

  @version 9.2
  @author Allan Bowe

**/

%macro mp_updatevarlength(libds,var,len
)/*/STORE SOURCE*/;

%mp_abort(iftrue=(%mf_existds(&libds)=0)
  ,mac=&sysmacroname
  ,msg=%str(Table &libds not found!)
)

%mp_abort(iftrue=(%mf_existvar(&libds,&var)=0)
  ,mac=&sysmacroname
  ,msg=%str(Variable &var not found on &libds!)
)

/* not possible to in-place modify a numeric length, to add later */
%mp_abort(iftrue=(%mf_getvartype(&libds,&var)=0)
  ,mac=&sysmacroname
  ,msg=%str(Only character resizings are currently supported)
)

%local oldlen;
%let oldlen=%mf_getvarlen(&libds,&var);
%if  &oldlen=&len %then %do;
  %put &sysmacroname: Old and new lengths (&len) match!;
  %return;
%end;

proc sql;
alter table &libds modify &var char(&len);

%mend;