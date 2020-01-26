import os

# Concatenate all macros into a single file
header="""
/**
  @file
  @brief Auto-generated file
  @details
    This file contains all the macros in a single file - which means it can be
    'included' in SAS with just 2 lines of code:

      filename mc url
        "https://raw.githubusercontent.com/macropeople/macrocore/master/compileall.sas";
      %inc mc;

    The `build.py` file in the https://github.com/macropeople/macrocore repo
    is used to create this file.

  @author Allan Bowe
**/
"""
f = open('compileall.sas', "w")             # r / r+ / rb / rb+ / w / wb
f.write(header)
folders=['base','meta','xcmd','viya']
for folder in folders:
    filenames=os.listdir('./' + folder) 
    with open('compile' + folder + '.sas', 'w') as outfile:
        for fname in filenames:
            with open('./' + folder + '/' + fname) as infile:
                outfile.write(infile.read())
    with open('compile' + folder + '.sas','r') as c:
        f.write(c.read())
f.close()

# Prepare Lua Macros 

