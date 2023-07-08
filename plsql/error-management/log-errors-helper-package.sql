
/*
The LOG ERRORS feature allows you to suppress errors at the row level in DML statements. 
Instead of raising the error, the error information is written to a log table (generated by a call
to DBMS_ERRLOG.CREATE_ERROR_LOG). But the design of the log table leaves a few things to 
be desired (doesn't include when the error occurred, "who" did it, and where in the code stack 
the statement was executed). This package helps "fill the gap" by creating the log table, 
altering it to add key columns and a trigger to set their values, and generate a package 
to make it easier to manage the table.
*/

CREATE OR REPLACE PACKAGE pkg1 AUTHID DEFINER 
IS  
   PROCEDURE proc1;  
END pkg1; 
/

-- Down to Subprogram Name!
-- The FORMAT_CALL_STACK function in DBMS_UTILITY only shows you the name of the program unit 
-- in the call stack (i.e., the package name, but not the function within the package). 
-- UTL_CALL_STACK only shows you the name of the package subprogram, but even the name of 
-- nested (local) subprograms within those. VERY COOL!
CREATE OR REPLACE PACKAGE BODY pkg1  
IS  
   PROCEDURE proc1  
   IS  
      PROCEDURE nested_in_proc1  
      IS  
      BEGIN  
         DBMS_OUTPUT.put_line ( 
            '*** "Traditional" Call Stack using FORMAT_CALL_STACK'); 
 
         DBMS_OUTPUT.put_line (DBMS_UTILITY.format_call_stack); 
  
         DBMS_OUTPUT.put_line ( 
            '*** Fully Qualified Nested Subprogram vis UTL_CALL_STACK');  
 
         DBMS_OUTPUT.put_line (  
            utl_call_stack.concatenate_subprogram (  
               utl_call_stack.subprogram (1)));  
      END;  
   BEGIN  
      nested_in_proc1;  
   END;  
END pkg1; 
/

-- The Call Stack Output
-- First, you will see the "Traditional" formatted call stack, next the fully-qualified name of the top of that stack, culled out of the "mess" with the UTL_CALL_STACK API.
BEGIN  
   pkg1.proc1;  
END; 
/

-- Backtrace Info, Too!
-- Need to get the line number on which an error was raised? You can stick with DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, sure. But now you can also opt for the UTL_CALL_STACK backtrace functions!
CREATE OR REPLACE FUNCTION backtrace_to  
   RETURN VARCHAR2 AUTHID DEFINER  
IS  
BEGIN  
   RETURN     
      utl_call_stack.backtrace_unit ( 
         utl_call_stack.backtrace_depth)  
      || ' line '  
      || utl_call_stack.backtrace_line ( 
             utl_call_stack.backtrace_depth);  
END; 
/

CREATE OR REPLACE PACKAGE pkg1 AUTHID DEFINER  
IS  
   PROCEDURE proc1;  
  
   PROCEDURE proc2;  
END; 
/

CREATE OR REPLACE PACKAGE BODY pkg1 
IS 
   PROCEDURE proc1 
   IS 
      PROCEDURE nested_in_proc1 
      IS 
      BEGIN 
         RAISE VALUE_ERROR; 
      END; 
   BEGIN 
      nested_in_proc1; 
   END; 
 
   PROCEDURE proc2 
   IS 
   BEGIN 
      proc1; 
   EXCEPTION 
      WHEN OTHERS 
      THEN 
         RAISE NO_DATA_FOUND; 
   END; 
END pkg1; 
/

CREATE OR REPLACE PROCEDURE proc3 AUTHID DEFINER  
IS  
BEGIN  
   pkg1.proc2;  
END; 
/

BEGIN  
   proc3;  
EXCEPTION  
   WHEN OTHERS  
   THEN  
      DBMS_OUTPUT.put_line (backtrace_to);  
END; 
/

-- Package Specification
-- The create_objects procedure (overloaded) calls the built-in DBMS_ERRLOG.create_error_log procedure, and then takes some other steps.
CREATE OR REPLACE PACKAGE dbms_errlog_helper  
   AUTHID CURRENT_USER  
/*  
| File name: dbms_errlog_helper.sql  
|  
| Author: Steven Feuerstein, steven.feuerstein@oracle.com 
|  
| Overview: Run this program to create a database error log table  
|   (via the DBMS_ERRLOG mechanism) so that you can log errors for  
|   this table and continue processing DML statements. It will also  
|   generate a helper package for the specified table that you can  
|   use after running the DML statement(s) so you can easily view  
|   and manage any errors that are raised. Finally, it automatically  
|   adds audit columns created_by and created_on so you can keep  
|   track of where and when the errors were added, and a trigger is  
|   defined on the table to populate those columns.  
|  
| TO DO  
|   * Execute grants on error log table so that anyone who can make  
|     a change to the DML table can insert into the log table.  
|  
| Modification History:  
|   Date        Who         What  
|  
| Dec 2008      SF          Stop creating the trigger with a static name.  
|                           Instead, the name varies by the table name.  
|                           Add option to clear error log after retrieval.  
|  
| Mar 2008      SF          Create audit columns, create trigger,  
|                           change to AUTHID CURRENT_USER.  
|  
| Feb 2008      SF          Convert to package that offers ability  
|                           to immediately compile package rather  
|                           than return CLOBS.  
|  
| Oct 3 2007    SF          Carve out from q$error_manager to make it  
|                           available as a stand-alone utility.  
|  
*/  
IS  
   PROCEDURE create_objects (dml_table_name           VARCHAR2  
                           , err_log_table_name       VARCHAR2 DEFAULT NULL  
                           , err_log_table_owner      VARCHAR2 DEFAULT NULL  
                           , err_log_table_space      VARCHAR2 DEFAULT NULL  
                           , skip_unsupported         BOOLEAN DEFAULT FALSE  
                           , overwrite_log_table      BOOLEAN DEFAULT TRUE  
                           , err_log_package_name     VARCHAR2 DEFAULT NULL  
                           , err_log_package_spec OUT DBMS_SQL.varchar2s  
                           , err_log_package_body OUT DBMS_SQL.varchar2s  
                            );  
  
   PROCEDURE create_objects (dml_table_name           VARCHAR2  
                           , err_log_table_name       VARCHAR2 DEFAULT NULL  
                           , err_log_table_owner      VARCHAR2 DEFAULT NULL  
                           , err_log_table_space      VARCHAR2 DEFAULT NULL  
                           , skip_unsupported         BOOLEAN DEFAULT FALSE  
                           , overwrite_log_table      BOOLEAN DEFAULT TRUE  
                           , err_log_package_name     VARCHAR2 DEFAULT NULL  
                           , err_log_package_spec OUT VARCHAR2  
                           , err_log_package_body OUT VARCHAR2  
                            );  
  
   PROCEDURE create_objects (dml_table_name        VARCHAR2  
                           , err_log_table_name    VARCHAR2 DEFAULT NULL  
                           , err_log_table_owner   VARCHAR2 DEFAULT NULL  
                           , err_log_table_space   VARCHAR2 DEFAULT NULL  
                           , skip_unsupported      BOOLEAN DEFAULT FALSE  
                           , overwrite_log_table   BOOLEAN DEFAULT TRUE  
                           , err_log_package_name  VARCHAR2 DEFAULT NULL  
                            );  
END dbms_errlog_helper; 
/

-- Package Body
-- I love using dynamic SQL to perform tasks like this. Of course, you'd have to be very careful if this was running in production (and users could supply text), but this is a developer utility. So don't worry, be happy!
CREATE OR REPLACE PACKAGE BODY dbms_errlog_helper  
IS  
   /*  
   | Overview: Run this program to create a database error log table  
   |   (via the DBMS_ERRLOG mechanism) so that you can log errors for  
   |   this table and continue processing DML statements. It will also  
   |   generate a helper package for the specified table that you can  
   |   use after running the DML statement(s) so you can easily view  
   |   and manage any errors that are raised  
   |  
   | Author(s): Steven Feuerstein  
   |  
   | Modification History:  
   |   Date        Who         What  
   | Feb 2008      SF          Convert to package that offers ability  
   |                           to immediately compile package rather  
   |                           return CLOBS.A  
   | Oct 3 2007    SF          Carve out from q$error_manager to make it  
   |                           available as a stand-alone utility.  
   |  
   */  
 
   SUBTYPE maxvarchar2_t IS VARCHAR2 (32767);  
  
   PROCEDURE create_objects (dml_table_name           VARCHAR2  
                           , err_log_table_name       VARCHAR2 DEFAULT NULL  
                           , err_log_table_owner      VARCHAR2 DEFAULT NULL  
                           , err_log_table_space      VARCHAR2 DEFAULT NULL  
                           , skip_unsupported         BOOLEAN DEFAULT FALSE  
                           , overwrite_log_table      BOOLEAN DEFAULT TRUE  
                           , err_log_package_name     VARCHAR2 DEFAULT NULL  
                           , err_log_package_spec OUT DBMS_SQL.varchar2s  
                           , err_log_package_body OUT DBMS_SQL.varchar2s  
                            )  
   IS  
      PRAGMA AUTONOMOUS_TRANSACTION;  
      c_package_name CONSTANT maxvarchar2_t  
            := SUBSTR (NVL (err_log_package_name, 'ELP$_' || dml_table_name)  
                     , 1  
                     , 30  
                      ) ;  
      c_errlog_table_name CONSTANT maxvarchar2_t  
            := SUBSTR (NVL (err_log_table_name, 'ERR$_' || dml_table_name)  
                     , 1  
                     , 30  
                      ) ;  
      c_qual_errlog_table_name CONSTANT maxvarchar2_t  
            := CASE  
                  WHEN err_log_table_owner IS NULL THEN NULL  
                  ELSE err_log_table_owner || '.'  
               END  
               || c_errlog_table_name ;  
      l_spec   DBMS_SQL.varchar2s;  
      l_body   DBMS_SQL.varchar2s;  
  
      PROCEDURE create_error_log  
      IS  
      BEGIN  
         IF overwrite_log_table  
         THEN  
            BEGIN  
               EXECUTE IMMEDIATE 'DROP TABLE ' || c_qual_errlog_table_name;  
            EXCEPTION  
               WHEN OTHERS  
               THEN  
                  NULL;  
            END;  
         END IF;  
  
         /*  
         Create the error log; any errors raised by this program will  
         terminate the rest of the processing of this helper program.  
         */  
         DBMS_ERRLOG.create_error_log (  
            dml_table_name        => dml_table_name  
          , err_log_table_name    => err_log_table_name  
          , err_log_table_owner   => err_log_table_owner  
          , err_log_table_space   => err_log_table_space  
          , skip_unsupported      => skip_unsupported  
         );  
  
         /* Alter the error log table to add audit columns. */  
         EXECUTE IMMEDIATE 'ALTER TABLE ' || NVL (err_log_table_owner, USER)   
            || '.' || c_errlog_table_name || ' ADD created_by VARCHAR2(30)';  
  
         EXECUTE IMMEDIATE 'ALTER TABLE ' || NVL (err_log_table_owner, USER)   
            || '.' || c_errlog_table_name || ' ADD created_on DATE';  
  
         /* Add Call Stack: Thanks, IFMC! */  
         EXECUTE IMMEDIATE 'ALTER TABLE ' || NVL (err_log_table_owner, USER)   
            || '.' || c_errlog_table_name || ' ADD call_stack VARCHAR2(4000)';  
  
         /* Add the trigger to update these columns. */  
         EXECUTE IMMEDIATE 'CREATE OR REPLACE TRIGGER '   
         || SUBSTR (dml_table_name || '$BEF_EL', 1, 30)   
         || ' BEFORE INSERT OR UPDATE ON ' || NVL (err_log_table_owner, USER)   
         || '.' || c_errlog_table_name || ' FOR EACH ROW BEGIN :NEW.created_by := USER; '   
         || ' :NEW.created_on := SYSDATE; ' || ' :NEW.call_stack := '   
         || 'SUBSTR (dbms_utility.Format_call_stack (), 1, 4000); END;';  
      END create_error_log;  
  
      PROCEDURE generate_spec (package_name_in IN     VARCHAR2  
                             , code_out           OUT DBMS_SQL.varchar2s  
                              )  
      IS  
         PROCEDURE add_line (line_in IN VARCHAR2)  
         IS  
         BEGIN  
            l_spec (l_spec.COUNT + 1) := line_in;  
         END add_line;  
      BEGIN  
         add_line ('CREATE OR REPLACE PACKAGE ' || c_package_name || ' IS ');  
         add_line(   'SUBTYPE error_log_r IS '  
                  || c_qual_errlog_table_name  
                  || '%ROWTYPE;');  
         add_line(   'TYPE error_log_tc IS TABLE OF '  
                  || c_qual_errlog_table_name  
                  || '%ROWTYPE;');  
         add_line ('PROCEDURE clear_error_log;');  
         add_line ('FUNCTION error_log_contents (');  
         add_line ('  ORA_ERR_NUMBER$_IN IN PLS_INTEGER DEFAULT NULL');  
         add_line (', ORA_ERR_OPTYP$_IN IN VARCHAR2 DEFAULT NULL');  
         add_line (', ORA_ERR_TAG$_IN IN VARCHAR2 DEFAULT NULL');  
         add_line (', where_in IN VARCHAR2 DEFAULT NULL');  
         add_line (', preserve_log_in IN BOOLEAN DEFAULT TRUE');  
         add_line (') RETURN error_log_tc;');  
         -- add_line ('PROCEDURE dump_error_log;');  
         add_line ('END ' || c_package_name || ';');  
         code_out := l_spec;  
      END generate_spec;  
  
      PROCEDURE generate_body (package_name_in IN     VARCHAR2  
                             , code_out           OUT DBMS_SQL.varchar2s  
                              )  
      IS  
         PROCEDURE add_line (line_in IN VARCHAR2)  
         IS  
         BEGIN  
            l_body (l_body.COUNT + 1) := line_in;  
         END add_line;  
      BEGIN  
         add_line (  
            'CREATE OR REPLACE PACKAGE BODY ' || c_package_name || ' IS '  
         );  
         add_line ('PROCEDURE clear_error_log');  
         add_line ('IS PRAGMA AUTONOMOUS_TRANSACTION; BEGIN ');  
         add_line ('DELETE FROM ' || c_qual_errlog_table_name || '; COMMIT;');  
         add_line ('END clear_error_log;');  
         add_line ('FUNCTION error_log_contents (');  
         add_line ('  ORA_ERR_NUMBER$_IN IN PLS_INTEGER DEFAULT NULL');  
         add_line (', ORA_ERR_OPTYP$_IN IN VARCHAR2 DEFAULT NULL');  
         add_line (', ORA_ERR_TAG$_IN IN VARCHAR2 DEFAULT NULL');  
         add_line (', where_in IN VARCHAR2 DEFAULT NULL');  
         add_line (', preserve_log_in IN BOOLEAN DEFAULT TRUE');  
         add_line (') RETURN error_log_tc');  
         add_line (' IS ');  
         add_line('l_query      VARCHAR2 (32767)  
         :=    ''SELECT * FROM '  
                  || c_qual_errlog_table_name  
                  || ' WHERE ( ora_err_number$ LIKE :ora_err_number$_in  
              OR :ora_err_number$_in IS NULL');  
         add_line(') AND (   ora_err_optyp$ LIKE :ora_err_optyp$_in  
              OR :ora_err_optyp$_in IS NULL )');  
         add_line('AND (ora_err_tag$ LIKE :ora_err_tag$_in OR :ora_err_tag$_in IS NULL)''  
            || CASE WHEN where_in IS NULL');  
         add_line('THEN NULL ELSE '' AND '' || REPLACE (where_in, '''''''', '''''''''''') END;  
      l_log_rows   error_log_tc;');  
         add_line (  
            'BEGIN EXECUTE IMMEDIATE l_query BULK COLLECT INTO l_log_rows'  
         );  
         add_line('USING ORA_ERR_NUMBER$_IN, ORA_ERR_NUMBER$_IN,  
               ORA_ERR_OPTYP$_IN, ORA_ERR_OPTYP$_IN,  
               ORA_ERR_TAG$_IN, ORA_ERR_TAG$_IN; RETURN l_log_rows;');  
         add_line ('IF NOT preserve_log_in THEN clear_error_log(); END IF;');  
         add_line('EXCEPTION WHEN OTHERS THEN  
         DBMS_OUTPUT.put_line (''Error retrieving log contents for :'');  
         DBMS_OUTPUT.put_line (DBMS_UTILITY.format_error_stack);  
         DBMS_OUTPUT.put_line (l_query);  
         RAISE;');  
         add_line ('END error_log_contents; END ' || c_package_name || ';');  
         code_out := l_body;  
      END generate_body;  
   BEGIN  
      create_error_log;  
      generate_spec (c_package_name, err_log_package_spec);  
      generate_body (c_package_name, err_log_package_body);  
   END create_objects;  
  
   PROCEDURE create_objects (dml_table_name           VARCHAR2  
                           , err_log_table_name       VARCHAR2 DEFAULT NULL  
                           , err_log_table_owner      VARCHAR2 DEFAULT NULL  
                           , err_log_table_space      VARCHAR2 DEFAULT NULL  
                           , skip_unsupported         BOOLEAN DEFAULT FALSE  
                           , overwrite_log_table      BOOLEAN DEFAULT TRUE  
                           , err_log_package_name     VARCHAR2 DEFAULT NULL  
                           , err_log_package_spec OUT VARCHAR2  
                           , err_log_package_body OUT VARCHAR2  
                            )  
   IS  
      l_spec          DBMS_SQL.varchar2s;  
      l_body          DBMS_SQL.varchar2s;  
      l_spec_string   maxvarchar2_t;  
      l_body_string   maxvarchar2_t;  
   BEGIN  
      create_objects (dml_table_name         => dml_table_name  
                    , err_log_table_name     => err_log_table_name  
                    , err_log_table_owner    => err_log_table_owner  
                    , err_log_table_space    => err_log_table_space  
                    , skip_unsupported       => skip_unsupported  
                    , overwrite_log_table    => overwrite_log_table  
                    , err_log_package_name   => err_log_package_name  
                    , err_log_package_spec   => l_spec  
                    , err_log_package_body   => l_body  
                     );  
  
      FOR indx IN 1 .. l_spec.COUNT  
      LOOP  
         l_spec_string :=  
            CASE  
               WHEN indx = 1 THEN l_spec (indx)  
               ELSE l_spec_string || CHR (10) || l_spec (indx)  
            END;  
      END LOOP;  
  
      FOR indx IN 1 .. l_body.COUNT  
      LOOP  
         l_body_string :=  
            CASE  
               WHEN indx = 1 THEN l_body (indx)  
               ELSE l_body_string || CHR (10) || l_body (indx)  
            END;  
      END LOOP;  
  
      err_log_package_spec := l_spec_string;  
      err_log_package_body := l_body_string;  
   END create_objects;  
  
   PROCEDURE create_objects (dml_table_name        VARCHAR2  
                           , err_log_table_name    VARCHAR2 DEFAULT NULL  
                           , err_log_table_owner   VARCHAR2 DEFAULT NULL  
                           , err_log_table_space   VARCHAR2 DEFAULT NULL  
                           , skip_unsupported      BOOLEAN DEFAULT FALSE  
                           , overwrite_log_table   BOOLEAN DEFAULT TRUE  
                           , err_log_package_name  VARCHAR2 DEFAULT NULL  
                            )  
   IS  
      PRAGMA AUTONOMOUS_TRANSACTION;  
      l_spec   DBMS_SQL.varchar2s;  
      l_body   DBMS_SQL.varchar2s;  
  
      PROCEDURE compile_statement (array_in IN DBMS_SQL.varchar2s)  
      IS  
         l_cur   PLS_INTEGER := DBMS_SQL.open_cursor;  
      BEGIN  
         DBMS_SQL.parse (l_cur  
                       , array_in  
                       , 1  
                       , array_in.COUNT  
                       , TRUE  
                       , DBMS_SQL.native  
                        );  
         DBMS_SQL.close_cursor (l_cur);  
      END compile_statement;  
   BEGIN  
      create_objects (dml_table_name         => dml_table_name  
                    , err_log_table_name     => err_log_table_name  
                    , err_log_table_owner    => err_log_table_owner  
                    , err_log_table_space    => err_log_table_space  
                    , skip_unsupported       => skip_unsupported  
                    , overwrite_log_table    => overwrite_log_table  
                    , err_log_package_name   => err_log_package_name  
                    , err_log_package_spec   => l_spec  
                    , err_log_package_body   => l_body  
                     );  
      compile_statement (l_spec);  
      compile_statement (l_body);  
   EXCEPTION  
      WHEN OTHERS THEN dbms_output.put_line (dbms_utility.format_error_backtrace); raise; 
   END create_objects;  
END dbms_errlog_helper; 
/

-- Run the Helper Package Through Some Paces
CREATE TABLE employees AS SELECT * FROM hr.employees ;

-- Run the Helper Package Through Some Paces
BEGIN 
   dbms_errlog_helper.create_objects ('EMPLOYEES'); 
END; 
/

-- Run the Helper Package Through Some Paces
SELECT column_id, column_name 
  FROM user_tab_columns 
 WHERE table_name = 'ERR$_EMPLOYEES' ;

-- Run the Helper Package Through Some Paces
SELECT text 
  FROM user_source 
 WHERE name = 'ELP$_EMPLOYEES' 
 ORDER BY line ;

-- Run the Helper Package Through Some Paces
DECLARE 
   l_count   PLS_INTEGER; 
BEGIN 
   SELECT COUNT ( * ) 
     INTO l_count 
     FROM employees 
    WHERE salary > 24000; 
 
   DBMS_OUTPUT.put_line ('Before ' || l_count); 
 
       UPDATE employees 
          SET salary = salary * 200 
   LOG ERRORS REJECT LIMIT UNLIMITED; 
 
   SELECT COUNT ( * ) 
     INTO l_count 
     FROM employees 
    WHERE salary > 24000; 
 
   DBMS_OUTPUT.put_line ('After ' || l_count); 
 
   ROLLBACK; 
END; 
/

-- Run the Helper Package Through Some Paces
DECLARE 
   l_errors   elp$_employees.error_log_tc; 
BEGIN 
   l_errors := elp$_employees.error_log_contents; 
 
   FOR indx IN 1 .. l_errors.COUNT 
   LOOP 
      DBMS_OUTPUT.put_line ( 
         l_errors (indx).ora_err_mesg$ || ' - ' || l_errors (indx).last_name 
      ); 
   END LOOP; 
END; 
/

