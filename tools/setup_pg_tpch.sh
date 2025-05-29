#!/bin/bash
apt update
apt install -y git build-essential
git clone https://github.com/gregrahn/tpch-kit.git
cd tpch-kit/dbgen
make
./dbgen -s 1
psql -U postgres -c 'CREATE DATABASE tpch;'
psql -U postgres -d tpch -f dss.ddl
for table in customer lineitem nation orders part partsupp region supplier; do
  psql -U postgres -d tpch -c "COPY $table FROM '$(pwd)/$table.tbl' WITH DELIMITER '|' CSV;"
done

sed -i -e 's/TPCD[.]//g' dss.ri
psql -U postgres -d tpch -f dss.ri

psql -U postgres -d tpch -c 'ALTER TABLE part ADD COLUMN p_doc jsonb;'
psql -U postgres -d tpch -c "UPDATE part SET p_doc = jsonb_build_object( 'part_id', p_partkey, 'name', p_name, 'manufacturer', p_mfgr, 'brand', p_brand, 'type', p_type, 'size', p_size, 'container', p_container, 'retail_price', p_retailprice, 'comment', p_comment, 'large_data', array_to_string(ARRAY(SELECT substr(md5(random()::text), 1, 10) FROM generate_series(1, 1000)), ' ')  );"
