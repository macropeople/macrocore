/**
  @file mf_isblank.sas
  @brief Checks whether a macro variable is empty (blank)
  @details Simply performs:

    %sysevalf(%superq(param)=,boolean)

  @param param NAME of the macro variable to be checked (not value)

  @return output returns 1 (if blank) else 0

  @version 9.2
**/

%macro mf_isblank(param
)/*/STORE SOURCE*/;

  %sysevalf(%superq(param)=,boolean)

%mend;