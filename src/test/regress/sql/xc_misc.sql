--
-- XC_MISC
--

-- A function to return a unified data node name given a node identifer 
create or replace function get_unified_node_name(node_ident int) returns varchar language plpgsql as $$
declare
	r pgxc_node%rowtype;
	node int;
	nodenames_query varchar;
begin
	nodenames_query := 'SELECT * FROM pgxc_node  WHERE node_type = ''D'' ORDER BY xc_node_id';

	node := 1;
	for r in execute nodenames_query loop
		if r.node_id = node_ident THEN
			RETURN 'NODE_' || node;
		end if;
		node := node + 1;
	end loop;
	RETURN 'NODE_?';
end;
$$;

-- Test the system column added by XC called xc_node_id, used to find which tuples belong to which data node

select create_table_nodes('t1_misc(a int, b int)', '{1, 2}'::int[], 'modulo(a)', NULL);
insert into t1_misc values(1,11),(2,11),(3,11),(4,22),(5,22),(6,33),(7,44),(8,44);

select get_unified_node_name(xc_node_id),* from t1_misc order by a;

select get_unified_node_name(xc_node_id),* from t1_misc where xc_node_id IS NOT NULL order by a;

create table t2_misc(a int , xc_node_id int) distribute by modulo(a);

create table t2_misc(a int , b int) distribute by modulo(xc_node_id);

drop table t1_misc;

-- Test an SQL function with multiple statements in it including a utility statement.

create table my_tab1 (a int);

insert into my_tab1 values(1);

create function f1 () returns setof my_tab1 as $$ create table my_tab2 (a int); select * from my_tab1; $$ language sql;

SET check_function_bodies = false;

create function f1 () returns setof my_tab1 as $$ create table my_tab2 (a int); select * from my_tab1; $$ language sql;

select f1();

SET check_function_bodies = true;

drop function f1();

-- Test pl-pgsql functions containing utility statements

CREATE OR REPLACE FUNCTION test_fun_2() RETURNS SETOF my_tab1 AS '
DECLARE
   t1 my_tab1;
   occ RECORD;
BEGIN
   CREATE TABLE tab4(a int);
   CREATE TABLE tab5(a int);

   FOR occ IN SELECT * FROM my_tab1
   LOOP
     t1.a := occ.a;
     RETURN NEXT t1;
   END LOOP;

   RETURN;
END;' LANGUAGE 'plpgsql';

select test_fun_2();

drop function test_fun_2();

drop table tab4;
drop table tab5;
drop table my_tab1;

-- Test to make sure that the
-- INSERT SELECT in case of inserts into a child by selecting from
-- a parent works fine

create table t_11 ( a int, b int);
create table t_22 ( a int, b int);
insert into t_11 values(1,2),(3,4);
insert into t_22 select * from t_11; -- should pass

CREATE TABLE c_11 () INHERITS (t_11);
insert into c_11 select * from t_22; -- should pass
insert into c_11 select * from t_11; -- should insert 2
insert into c_11 (select * from t_11 union all select * from t_22);
insert into c_11 (select t_11.a, t_22.b from t_11,t_22);
insert into c_11 (select * from t_22 where a in (select a from t_11)); -- should pass
insert into c_11 (select * from t_11 where a in (select a from t_22));
insert into t_11 select * from c_11; -- should pass

-- test to make sure count from a parent table works fine
select count(*) from t_11;

CREATE TABLE grand_parent (code int, population float, altitude int);
INSERT INTO grand_parent VALUES (0, 1.1, 63);
CREATE TABLE my_parent (code int, population float, altitude int);
INSERT INTO my_parent VALUES (1, 2.1, 73);
CREATE TABLE child_11 () INHERITS (my_parent);
CREATE TABLE grand_child () INHERITS (child_11);

INSERT INTO child_11 SELECT * FROM grand_parent; -- should pass
INSERT INTO child_11 SELECT * FROM my_parent;
INSERT INTO grand_child SELECT * FROM my_parent; -- should pass
INSERT INTO grand_child SELECT * FROM grand_parent; -- should pass

drop table grand_child;
drop table child_11;
drop table my_parent;
drop table grand_parent;
drop table c_11;
drop table t_22;
drop table t_11;

---------------------------------
-- Ensure that command ids are sent to data nodes and are reported back to coordinator
---------------------------------
create table my_tbl( f1 int);

begin;
 insert into my_tbl values(100),(101),(102),(103),(104),(105);
end;

select cmin, cmax, * from my_tbl order by f1; -- command id should be in sequence and increasing

---------------------------------
-- Ensure that command id is consumed by declare cursor
---------------------------------
begin;
 DECLARE c1 CURSOR FOR SELECT * FROM my_tbl;
 INSERT INTO my_tbl VALUES (200);
 select cmin, cmax,* from my_tbl where f1 = 200; -- should give 1 as command id of row containing 200
end;

---------------------------------
-- insert into child by seleting from parent
---------------------------------
create table tt_11 ( a int, b int);
insert into tt_11 values(1,2),(3,4);

CREATE TABLE cc_11 () INHERITS (tt_11);
insert into cc_11 select * from tt_11;

select * from cc_11 order by a; -- should insert 2 rows

begin;
 insert into cc_11 values(5,6);
 insert into cc_11 select * from tt_11; -- should insert the row (5,6)
end;

select * from cc_11 order by a;

---------------------------------

create table tt_33 ( a int, b int);
insert into tt_33 values(1,2),(3,4);

CREATE TABLE cc_33 () INHERITS (tt_33);
insert into cc_33 select * from tt_33;

begin;
 insert into cc_33 values(5,6);
 insert into cc_33 select * from tt_33; -- should insert row (5,6)
 insert into cc_33 values(7,8);
 select * from cc_33 order by a;
 insert into cc_33 select * from tt_33; -- should insert row (7,8)
end;

select * from cc_33 order by a;

---------------------------------
-- Ensure that rows inserted into the table after declaring the cursor do not show up in fetch
---------------------------------
CREATE TABLE tt_22 (a int, b int) distribute by replication;

INSERT INTO tt_22 VALUES (10);

BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
DECLARE c1 NO SCROLL CURSOR FOR SELECT * FROM tt_22 ORDER BY a FOR UPDATE;
INSERT INTO tt_22 VALUES (2);
FETCH ALL FROM c1; -- should not show the row (2)
END;

BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
DECLARE c1 NO SCROLL CURSOR FOR SELECT * FROM tt_22 ORDER BY a FOR UPDATE;
INSERT INTO tt_22 VALUES (3);
FETCH ALL FROM c1; -- should not show the row (3)

DECLARE c2 NO SCROLL CURSOR FOR SELECT * FROM tt_22 ORDER BY a FOR UPDATE;
INSERT INTO tt_22 VALUES (4);
FETCH ALL FROM c2; -- should not show the row (4)

DECLARE c3 NO SCROLL CURSOR FOR SELECT * FROM tt_22 ORDER BY a FOR UPDATE;
INSERT INTO tt_22 VALUES (5);
FETCH ALL FROM c3; -- should not show the row (5)

END;

DROP TABLE tt_22;

-----------------------------------

drop table my_tbl;

drop table cc_33;
drop table tt_33;

drop table cc_11;
drop table tt_11;

------------------------------------------------------------------------------
-- Check data consistency of replicated tables both in case of FQS and NON-FQS
------------------------------------------------------------------------------

select create_table_nodes('rr(a int, b int)', '{1, 2}'::int[], 'replication', NULL);

-- A function to select data form table rr name by running the query on the passed node number
CREATE OR REPLACE FUNCTION select_data_from(nodenum int) RETURNS SETOF rr LANGUAGE plpgsql AS $$
DECLARE
	nodename	varchar;
	qry		varchar;
	r		rr%rowtype;
BEGIN
	nodename := (SELECT get_xc_node_name(nodenum));
	qry := 'EXECUTE DIRECT ON (' || nodename || ') ' || chr(39) || 'select * from rr order by 1' || chr(39);

	FOR r IN EXECUTE qry LOOP
		RETURN NEXT r;
	END LOOP;
	RETURN;
END;
$$;

set enable_fast_query_shipping=true;

insert into rr values(1,2);
select select_data_from(1);
select select_data_from(2);

insert into rr values(3,4),(5,6),(7,8);
select select_data_from(1);
select select_data_from(2);

update rr set b=b+1 where b=2;
select select_data_from(1);
select select_data_from(2);

update rr set b=b+1;
select select_data_from(1);
select select_data_from(2);

delete from rr where b=9;
select select_data_from(1);
select select_data_from(2);

delete from rr;
select select_data_from(1);
select select_data_from(2);

set enable_fast_query_shipping=false;

insert into rr values(1,2);
select select_data_from(1);
select select_data_from(2);

insert into rr values(3,4),(5,6),(7,8);
select select_data_from(1);
select select_data_from(2);

update rr set b=b+1 where b=2;
select select_data_from(1);
select select_data_from(2);

update rr set b=b+1;
select select_data_from(1);
select select_data_from(2);

delete from rr where b=9;
select select_data_from(1);
select select_data_from(2);

delete from rr;
select select_data_from(1);
select select_data_from(2);

set enable_fast_query_shipping=true;

DROP FUNCTION select_data_from( int);

drop table rr;



------------------------------------------------------------------------------
-- Check that the partition column updation check works fine
------------------------------------------------------------------------------

-- Updation of a view

CREATE TABLE pcu_base_tbl (a int PRIMARY KEY, b text DEFAULT 'Unspecified');
INSERT INTO pcu_base_tbl SELECT i, 'Row ' || i FROM generate_series(-2, 2) g(i);

CREATE VIEW rw_view1 AS SELECT * FROM pcu_base_tbl WHERE a>0;

INSERT INTO rw_view1 VALUES (3, 'Row 3');
INSERT INTO rw_view1 (a) VALUES (4);

UPDATE rw_view1 SET a=5 WHERE a=4;
UPDATE rw_view1 SET a=a WHERE a=4;
UPDATE rw_view1 SET b = lower(b);

CREATE TABLE pcu_base_tbl2 (a int, b int) distribute by hash(a);
INSERT INTO pcu_base_tbl2 VALUES (1,2), (4,5), (3,-3);

-- check a few join cases

UPDATE pcu_base_tbl set a = pcu_base_tbl2.a from pcu_base_tbl2 where pcu_base_tbl.a=pcu_base_tbl2.b;

UPDATE pcu_base_tbl set a = pcu_base_tbl.a from pcu_base_tbl2 where pcu_base_tbl.a=pcu_base_tbl2.b;

UPDATE pcu_base_tbl set a = pcu_base_tbl.a, b=pcu_base_tbl2.b from pcu_base_tbl2 where pcu_base_tbl.a=pcu_base_tbl2.b;

-- Drop tables

drop table pcu_base_tbl cascade;
drop table pcu_base_tbl2 cascade;


------------------------------------------------------------------------------
-- Check that the updates / deletes are using primary key when appropriate
-- to perfomr the operation
------------------------------------------------------------------------------

create table xc_t41(a int, b int) distribute by replication;
create table xc_t42(a int primary key, b int) distribute by replication;
create table xc_t43(a int, b int primary key) distribute by replication;
create table xc_t44(a int, b int, constraint pk PRIMARY KEY (a,b)) distribute by replication;

insert into xc_t41 values(1,2);
insert into xc_t41 values(3,4);
insert into xc_t41 values(5,6);

insert into xc_t42 values(1,2);
insert into xc_t42 values(3,4);
insert into xc_t42 values(5,6);

insert into xc_t43 values(1,2);
insert into xc_t43 values(3,4);
insert into xc_t43 values(5,6);

insert into xc_t44 values(1,2);
insert into xc_t44 values(3,4);
insert into xc_t44 values(5,6);

set enable_fast_query_shipping=false;

EXPLAIN (verbose true, costs off, nodes false) delete from xc_t41 where a = 1;
EXPLAIN (verbose true, costs off, nodes false) delete from xc_t42 where a = 1;
EXPLAIN (verbose true, costs off, nodes false) delete from xc_t43 where a = 1;
EXPLAIN (verbose true, costs off, nodes false) delete from xc_t44 where a = 1;

delete from xc_t41 where a = 1;
delete from xc_t42 where a = 1;
delete from xc_t43 where a = 1;
delete from xc_t44 where a = 1;

EXPLAIN (verbose true, costs off, nodes false) update xc_t41 set b = b + 1 where a = 3;
EXPLAIN (verbose true, costs off, nodes false) update xc_t42 set b = b + 1 where a = 3;
EXPLAIN (verbose true, costs off, nodes false) update xc_t43 set b = b + 1 where a = 3;
EXPLAIN (verbose true, costs off, nodes false) update xc_t44 set b = b + 1 where a = 3;

update xc_t41 set b = b + 1 where a = 3;
update xc_t42 set b = b + 1 where a = 3;
update xc_t43 set b = b + 1 where a = 3;
update xc_t44 set b = b + 1 where a = 3;


EXPLAIN (verbose true, costs off, nodes false) update xc_t41 set a = a + 1 where b = 6;
EXPLAIN (verbose true, costs off, nodes false) update xc_t42 set a = a + 1 where b = 6;
EXPLAIN (verbose true, costs off, nodes false) update xc_t43 set a = a + 1 where b = 6;
EXPLAIN (verbose true, costs off, nodes false) update xc_t44 set a = a + 1 where b = 6;

update xc_t41 set a = a + 1 where b = 6;
update xc_t42 set a = a + 1 where b = 6;
update xc_t43 set a = a + 1 where b = 6;
update xc_t44 set a = a + 1 where b = 6;

select * from xc_t41 order by 1, 2;
select * from xc_t42 order by 1, 2;
select * from xc_t43 order by 1, 2;
select * from xc_t44 order by 1, 2;

reset enable_fast_query_shipping;

drop table xc_t41;
drop table xc_t42;
drop table xc_t43;
drop table xc_t44;

------------------------------------------------------------------------------
-- Check that the GUC require_replicated_table_pkey changes the behavior
-- of updates and deletes to replicated tables as expected
------------------------------------------------------------------------------

create table xc_r1(a int, b int) distribute by replication;
insert into xc_r1 values(1,2),(3,4),(5,6);
set enable_fast_query_shipping = false;
set require_replicated_table_pkey = true;
update xc_r1 set b = b+1 where a = 1;
create table xc_r2(a int primary key, b int) distribute by replication;
insert into xc_r2 values(1,2),(3,4),(5,6);
update xc_r2 set b = b+1 where a = 1;
update xc_r2 set a = a+1 where b = 1;

set require_replicated_table_pkey = false;
update xc_r1 set b = b+1 where a = 1;
update xc_r2 set b = b+1 where a = 1;
update xc_r2 set a = a+1 where b = 1;

reset enable_fast_query_shipping;
reset require_replicated_table_pkey;

drop table xc_r1;
drop table xc_r2;

