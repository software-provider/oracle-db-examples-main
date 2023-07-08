This directory contains examples of fine-grained cursor invalidation.

The 'tests.sql' script is provided to give you ideas on how to try this feature out for yourself. There is a spool file tests.lst if you want to look at expected output.

The tests are in a raw state because I originally wrote the examples for my own benefit to explore the boundaries of this feature. In particular, there is a mixture of some DDL that *will* allow SQL statements to use rolling invalidation and some DDL that will not. There may be cases where a statement is accepted but it results in a no-op. Some of the PROMPT comments may be out of date because the test was created before Oracle Database 12c R2 was released.

My intention is to tidy up these scripts for Oracle Database 18c but I hope you will find them interesting now.

### Note

The example was run on Oracle Database 12c Release 2.

The tests are not intended to be 'full coverage' - there may be other cases that work.

The test case drops tables T1 and T2.

### DISCLAIMER

*  These scripts are provided for educational purposes only.
*  They are NOT supported by Oracle World Wide Technical Support.
*  The scripts have been tested and they appear to work as intended.
*  You should always run scripts on a test instance.

### WARNING

*  These scripts drop and create tables. For use on test databases
