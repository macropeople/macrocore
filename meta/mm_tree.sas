/**
  @file mm_tree.sas
  @brief Returns all folders / subfolder content for a particular root
  @details Shows all members and SubTrees for a particular root.

  Usage:

      * load macros;
      filename mc url "https://raw.githubusercontent.com/macropeople/macrocore/master/mc_all.sas";
      %inc mc;

      * export everything;
      %mm_tree(root= ,outds=iwantthisdataset)

      * export everything in a specific folder;
      %mm_tree(root=%str(/my/folder) ,outds=stuff)

      * export only folders;
      %mm_tree(root=%str(/my/folder) ,types=Folder ,outds=stuf)

      * with specific types;
      %mm_tree(root=%str(/my/folder)
        ,types= 
            DeployedJob 
            ExternalFile 
            Folder 
            Folder.SecuredData 
            GeneratedTransform 
            InformationMap.Relational 
            Job 
            Library 
            Prompt 
            StoredProcess
            Table
        ,outds=morestuff)

  <h4> Dependencies </h4>
  @li mf_getquotedstr.sas

  @param root= the parent folder under which to return all contents
  @param outds= the dataset to create that contains the list of directories
  @param types= Space-seperated, unquoted list of types for filtering the output.  

  @version 9.4
  @author Allan Bowe

**/
%macro mm_tree(
     root=
    ,types=ALL
    ,outds=work.mm_tree
)/*/STORE SOURCE*/;

%if &root= %then %let root=/;

* use a temporary fileref to hold the response;
filename response temp;
/* get list of libraries */
proc metadata in=
 '<GetMetadataObjects><Reposid>$METAREPOSITORY</Reposid>
   <Type>Tree</Type><Objects/><NS>SAS</NS>
   <Flags>384</Flags>
   <XMLSelect search="*[@TreeType=&apos;BIP Folder&apos;]"/>
   <Options/></GetMetadataObjects>'
  out=response;
run;
/*
data _null_;
  infile response;
  input;
  put _infile_;
  run;
*/

/* create an XML map to read the response */
filename sxlemap temp;
data _null_;
  file sxlemap;
  put '<SXLEMAP version="1.2" name="SASObjects"><TABLE name="SASObjects">';
  put "<TABLE-PATH syntax='XPath'>/GetMetadataObjects/Objects/Tree</TABLE-PATH>";
  put '<COLUMN name="pathuri">';
  put "<PATH syntax='XPath'>/GetMetadataObjects/Objects/Tree/@Id</PATH>";
  put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>64</LENGTH>";
  put '</COLUMN><COLUMN name="name">';
  put "<PATH syntax='XPath'>/GetMetadataObjects/Objects/Tree/@Name</PATH>";
  put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>256</LENGTH>";
  put '</COLUMN></TABLE></SXLEMAP>';
run;
libname _XML_ xml xmlfileref=response xmlmap=sxlemap;

data &outds;
  length metauri pathuri $64 name $256 path $1024
    publictype MetadataUpdated MetadataCreated $32;
  set _XML_.SASObjects;
  keep metauri name publictype MetadataUpdated MetadataCreated path;
  length parenturi pname $128 ;
  call missing(parenturi,pname);
  path=cats('/',name);
  /* get parents */
  tmpuri=pathuri;
  do while (metadata_getnasn(tmpuri,"ParentTree",1,parenturi)>0);
    rc=metadata_getattr(parenturi,"Name",pname);
    path=cats('/',pname,path);
    tmpuri=parenturi;
  end;
  
  if path=:"&root";

  %if &types=ALL or (&types ne ALL and &types ne Folder) %then %do;
    n=1;
    do while (metadata_getnasn(pathuri,"Members",n,metauri)>0);
      n+1;
      call missing(name,publictype,MetadataUpdated,MetadataCreated);
      rc=metadata_getattr(metauri,"Name", name);
      rc=metadata_getattr(metauri,"MetadataUpdated", MetadataUpdated);
      rc=metadata_getattr(metauri,"MetadataCreated", MetadataCreated);
      rc=metadata_getattr(metauri,"PublicType", PublicType);
    %if &types ne ALL %then %do;
      if publictype in (%mf_getquotedstr(&types)) then output;
    %end;
    %else output; ;
    end;
  %end;

  rc=metadata_resolve(pathuri,pname,tmpuri);
  metauri=cats('OMSOBJ:',pname,'\',pathuri);
  rc=metadata_getattr(metauri,"Name", name);
  rc=metadata_getattr(pathuri,"MetadataUpdated", MetadataUpdated);
  rc=metadata_getattr(pathuri,"MetadataCreated", MetadataCreated);
  rc=metadata_getattr(pathuri,"PublicType", PublicType);
  path=substr(path,1,length(path)-length(name));
  if publictype ne '' then output;
run;

proc sort;
  by path;
run;

/* clear references */
filename sxlemap clear;
filename response clear;
libname _XML_ clear;

%mend;
