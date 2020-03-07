# Change Log

All notable changes to this project will be documented in this file. See [standard-version](https://github.com/conventional-changelog/standard-version) for commit guidelines.

<a name="1.1.4"></a>
## [1.1.4](https://github.com/macropeople/macrocore/compare/v1.1.3...v1.1.4) (2020-03-07)



<a name="1.1.3"></a>
## [1.1.3](https://github.com/macropeople/macrocore/compare/v1.1.2...v1.1.3) (2020-03-07)



<a name="1.1.2"></a>
## [1.1.2](https://github.com/macropeople/macrocore/compare/v1.1.1...v1.1.2) (2020-03-07)



<a name="1.1.1"></a>
## [1.1.1](https://github.com/macropeople/macrocore/compare/v1.1.0...v1.1.1) (2020-03-05)


### Bug Fixes

* dealing with special characters in webout macros ([181f0f2](https://github.com/macropeople/macrocore/commit/181f0f2))



<a name="1.1.0"></a>
# [1.1.0](https://github.com/macropeople/macrocore/compare/v1.0.0...v1.1.0) (2020-03-02)


### Bug Fixes

* better error handling in mm_assignlib ([d5d967c](https://github.com/macropeople/macrocore/commit/d5d967c))
* duplicate extended property on getddl ([0f218b5](https://github.com/macropeople/macrocore/commit/0f218b5))
* formatting ([b93bab3](https://github.com/macropeople/macrocore/commit/b93bab3))
* formatting numerics: ([80c9f80](https://github.com/macropeople/macrocore/commit/80c9f80))
* glob var for sas9 ([24252c5](https://github.com/macropeople/macrocore/commit/24252c5))
* len issue on viya ([51f4629](https://github.com/macropeople/macrocore/commit/51f4629))
* length issue on sas9 ([b0479f7](https://github.com/macropeople/macrocore/commit/b0479f7))
* missing put ([dc659db](https://github.com/macropeople/macrocore/commit/dc659db))
* not all viya params are escaped, adding conditional logic in LUA ([e1ebc9a](https://github.com/macropeople/macrocore/commit/e1ebc9a))
* remove trailing newline in sas9 adapter ([454ad93](https://github.com/macropeople/macrocore/commit/454ad93))
* removing log messaging as can't read in _webout fileref in getddl ([e1d9853](https://github.com/macropeople/macrocore/commit/e1d9853))
* sas9 _webout truncation issue ([7a97d2e](https://github.com/macropeople/macrocore/commit/7a97d2e))
* sas9 _webout truncation issue2 ([6a391ab](https://github.com/macropeople/macrocore/commit/6a391ab))
* sas9 _webout truncation issue3 ([2a04542](https://github.com/macropeople/macrocore/commit/2a04542))
* sas9 fref issues ([ad007d2](https://github.com/macropeople/macrocore/commit/ad007d2))
* sas9 frefs ([84a46ec](https://github.com/macropeople/macrocore/commit/84a46ec))
* sas9 input ([0f0f3b2](https://github.com/macropeople/macrocore/commit/0f0f3b2))
* sas9 input vars ([0021af5](https://github.com/macropeople/macrocore/commit/0021af5))
* sas9 missing symbol ([9ea61d3](https://github.com/macropeople/macrocore/commit/9ea61d3))
* schema in TSQL for getDDL ([f4c0b53](https://github.com/macropeople/macrocore/commit/f4c0b53))
* scoping ([f40a8ac](https://github.com/macropeople/macrocore/commit/f40a8ac))
* shorter lua file ([0af7d50](https://github.com/macropeople/macrocore/commit/0af7d50))
* special nulls in SAS data ([f223e30](https://github.com/macropeople/macrocore/commit/f223e30))
* splitting fetch and open to prevent _webout misuse ([86237b5](https://github.com/macropeople/macrocore/commit/86237b5))
* viya vars without escaping ([b27848c](https://github.com/macropeople/macrocore/commit/b27848c))


### Features

* 2 new macros (mm_getroles and mm_getusers) ([1ee79f1](https://github.com/macropeople/macrocore/commit/1ee79f1))
* delete option when building new services ([b96e45d](https://github.com/macropeople/macrocore/commit/b96e45d))
* localhost option in mm_createwebservice ([9fae505](https://github.com/macropeople/macrocore/commit/9fae505))
* lua based viya adapter ([437db69](https://github.com/macropeople/macrocore/commit/437db69))
* mm_getrepos.sas macro for getting repositories ([5c5f719](https://github.com/macropeople/macrocore/commit/5c5f719))
* mp_getddl macro ([bcb9b56](https://github.com/macropeople/macrocore/commit/bcb9b56))
* mv_deletejes macro plus improved logging ([e15f2b0](https://github.com/macropeople/macrocore/commit/e15f2b0))



<a name="1.0.0"></a>
# 1.0.0 (2020-02-15)


### Bug Fixes

* enabling assignment when there are duplicate libnames in mm_assignlib ([d99bf43](https://github.com/macropeople/macrocore/commit/d99bf43))
* exit logic in mm_assignlib ([140dbcd](https://github.com/macropeople/macrocore/commit/140dbcd))
* rename xcmd folder to metax to differentiate between viya macros and SAS9 ([3dc3c9b](https://github.com/macropeople/macrocore/commit/3dc3c9b))


### Features

*  new macro (mp_searchcols) ([4f0e1b9](https://github.com/macropeople/macrocore/commit/4f0e1b9))
* adding index to cards file ([f046631](https://github.com/macropeople/macrocore/commit/f046631))
* adding repo option to getgroups macro ([533baeb](https://github.com/macropeople/macrocore/commit/533baeb))
* backend services ([c210133](https://github.com/macropeople/macrocore/commit/c210133))
* cleancsv macro ([6dc692b](https://github.com/macropeople/macrocore/commit/6dc692b))
* delete document macro ([c8661ea](https://github.com/macropeople/macrocore/commit/c8661ea))
* delete stp macro ([3df932c](https://github.com/macropeople/macrocore/commit/3df932c))
* enabling single param for _program in getstpcode and providing code in the mm_createwebservice macro ([8745a7c](https://github.com/macropeople/macrocore/commit/8745a7c))
* get folder tree macro ([4536bad](https://github.com/macropeople/macrocore/commit/4536bad))
* get tables macro ([0f7b2a8](https://github.com/macropeople/macrocore/commit/0f7b2a8))
* lua builder ([79b0263](https://github.com/macropeople/macrocore/commit/79b0263))
* mm_createfolder now works recursively ([9b0bdae](https://github.com/macropeople/macrocore/commit/9b0bdae))
* mv web service ([91054a1](https://github.com/macropeople/macrocore/commit/91054a1))
* new build script ([5ca9e94](https://github.com/macropeople/macrocore/commit/5ca9e94))
* new macro for searching columns ([b1efcfc](https://github.com/macropeople/macrocore/commit/b1efcfc))
* new macro to change the server type of an STP ([e006bea](https://github.com/macropeople/macrocore/commit/e006bea))
* new macro to create physical table from metadata definition ([4a84a5f](https://github.com/macropeople/macrocore/commit/4a84a5f))
* new mm_getcols macro ([19e5644](https://github.com/macropeople/macrocore/commit/19e5644))


### BREAKING CHANGES

* mx_deletemetafolder.sas moved to mmx_deletemetafolder.sas
