-- Single table in public schema:
CREATE SCHEMA core_data_tables;
COMMENT ON SCHEMA core_data_tables IS
$qq$
Contains the meta data  and data tables for the MacTire application.
$qq$;

CREATE TABLE core_data_tables.assays(
    assay_name TEXT PRIMARY KEY,
    assay_description TEXT);
COMMENT ON TABLE core_data_tables.assays IS
$qq$
This is the top-level table in the data model. All loaded data must belong to an "assay" where an assay is composed of attributes that are defined in the table "assay_attributes.
$qq$;

CREATE TABLE core_data_tables.assay_attributes(
    assay_attribute_name TEXT PRIMARY KEY,
    assay_attribute_type TEXT NOT NULL,
    assay_attribute_data_type TEXT NOT NULL,
    assay_attribute_description TEXT);
COMMENT ON TABLE core_data_tables.assay_attributes IS
$qq$ 
An assay is composed of one or more attributes and these can be either descriptive or a measurement of some type. 
All these attributes must be defined in this table.
$qq$;

CREATE TABLE core_data_tables.file_loads(
    file_load_id TEXT PRIMARY KEY,
    loaded_by TEXT NOT NULL,
    loaded_file_fullname TEXT,
    load_date DATE DEFAULT CURRENT_DATE);
COMMENT ON TABLE core_data_tables.file_loads IS
$qq$
Records information for data loading. It uses the source file ID hash value as a primary key to prevent duplicate loading of files.
$qq$;

CREATE TABLE core_data_tables.experiments(
    experiment_name TEXT PRIMARY KEY,
    experiment_description TEXT);
COMMENT ON TABLE core_data_tables.experiments IS
$qq$
An experiment is defined as a single run of an assay composed of one or more assay attributes. All such details are stored here.
$qq$;

CREATE TABLE core_data_tables.assay_data(
	  assay_data_id SERIAL PRIMARY KEY,
    experiment_name TEXT NOT NULL,
    file_load_id TEXT NOT NULL,
    data_row JSONB);
COMMENT ON TABLE core_data_tables.assay_data IS
$qq$
Stores all the actual data where it is stored in a key->value format using JSONB where the keys are the column headings
from the source file and the values are the data values with these column headings.
$qq$;

CREATE TABLE core_data_tables.assays_assay_attributes_files(
  assay_name TEXT,
  assay_attribute_name TEXT,
  file_load_id TEXT);
COMMENT ON TABLE core_data_tables.assays_assay_attributes_files IS
$qq$
A relationship table. For each data load, this table associates the assay, the assay attribute and the loaded file.
$qq$;

ALTER TABLE core_data_tables.assay_data ADD CONSTRAINT ad_fl_fk FOREIGN KEY(file_load_id) REFERENCES core_data_tables.file_loads(file_load_id);
ALTER TABLE core_data_tables.assay_data ADD CONSTRAINT ad_e_fk FOREIGN KEY(experiment_name) REFERENCES core_data_tables.experiments(experiment_name);
ALTER TABLE core_data_tables.assays_assay_attributes_files ADD CONSTRAINT aaaf_a_fk FOREIGN KEY(assay_name) REFERENCES core_data_tables.assays(assay_name);
ALTER TABLE core_data_tables.assays_assay_attributes_files ADD CONSTRAINT aaaf_aa_fk FOREIGN KEY(assay_attribute_name) REFERENCES core_data_tables.assay_attributes(assay_attribute_name);
ALTER TABLE core_data_tables.assays_assay_attributes_files ADD CONSTRAINT aaaf_fl_fk FOREIGN KEY(file_load_id) REFERENCES core_data_tables.file_loads(file_load_id);



-- Stored procedures
CREATE SCHEMA client_procedures;
COMMENT ON SCHEMA client_procedures IS
$qq$ Contains all the stored procedures needed by external clients. $qq$;

CREATE OR REPLACE FUNCTION client_procedures.load_data_to_transit_tmp(p_data_row TEXT)
RETURNS VOID
AS
$$
BEGIN
  INSERT INTO transit_tmp(data_row) VALUES(p_data_row);
END;
$$
LANGUAGE plpgsql
  SECURITY DEFINER;
COMMENT ON FUNCTION client_procedures.load_data_to_transit_tmp(TEXT) IS
$qq$
Simple function to load a data row (some sort of delimited row) into an unlogged holding table from where the data is then processed and pushed into target tables.
$qq$

CREATE OR REPLACE FUNCTION client_procedures.load_metadata(p_experiment_name TEXT,
                                                          p_assay_name TEXT,
                                                          p_username TEXT,
                                                          p_loaded_file_fullname TEXT,
                                                          p_assay_attribute_names TEXT,
                                                          p_assay_attribute_names_delimiter TEXT DEFAULT E'\t')
RETURNS TEXT
AS
$$
DECLARE
  l_assay_attribute_names TEXT[] := STRING_TO_ARRAY(p_assay_attribute_names, p_assay_attribute_names_delimiter);
  l_file_load_id TEXT := MD5(p_loaded_file_fullname);
BEGIN
  INSERT INTO core_data_tables.file_loads(file_load_id, loaded_by, loaded_file_fullname)
    VALUES(l_file_load_id, p_username, p_loaded_file_fullname);
  INSERT INTO core_data_tables.assays_assay_attributes_files(assay_name, assay_attribute_name, file_load_id)
  SELECT
    p_assay_name,
    UNNEST(l_assay_attribute_names),
    l_file_load_id;
  RETURN l_file_load_id;
END;
$$
LANGUAGE plpgsql
  SECURITY DEFINER;
COMMENT ON FUNCTION client_procedures.load_metadata(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) IS
$qq$
Purpose: Add metadata rows to tables "core_data_tables.file_loads" and "core_data_tables.assays_assay_attributes_files".
Referenced foreign keys have to pre-exist for this to work.
This function needs to be called before the actual data is transferred to table "core_data_tables.file_data".
The whole pipeline relies on referential integrity constraints to throw errors to abort invalid data load attempts.
Returns the hash code (MD5) for the full file name. Since this value is the primary key in the table "core_data_tables.file_loads",
Example call (assumes all FKs are pre-existing):
SELECT client_procedures.load_metadata(
  'test_experiment',
  'dummy assay',
  'no such user',
  'test file not excel',
  'raw_data_name	viable_cells	cd4_mfi_cd137	cd4_mfi_proliferation	cd4_mfi_cd25	cd4_percent_proliferation	cd4_percent_cd25	cd4_percent_cd137	cd8_mfi_cd137	cd8_mfi_proliferation	cd8_mfi_cd25	cd8_percent_proliferation	cd8_percent_cd25	cd8_percent_cd137	cd4_cell_number	cd8_cell_number	sample_identifier'
 );
$qq$;


CREATE OR REPLACE FUNCTION client_procedures.load_assay_data(p_assay_attribute_names TEXT, p_experiment_name TEXT, p_file_load_id TEXT, p_row_values_delimiter TEXT DEFAULT E'\t')
RETURNS INTEGER
AS
$$
DECLARE
  l_inserted_rowcount INTEGER;
  l_assay_attribute_names TEXT[] := STRING_TO_ARRAY(p_assay_attribute_names, p_row_values_delimiter); 
BEGIN
  INSERT INTO core_data_tables.assay_data(experiment_name, file_load_id, data_row)
  SELECT
    p_experiment_name,
    p_file_load_id,
    JSONB_OBJECT(l_assay_attribute_names, STRING_TO_ARRAY(data_row, p_row_values_delimiter))
  FROM
    transit_tmp;
  GET DIAGNOSTICS l_inserted_rowcount = ROW_COUNT;
  RETURN l_inserted_rowcount;
END;
$$
LANGUAGE plpgsql
  SECURITY DEFINER;
COMMENT ON FUNCTION client_procedures.load_assay_data(TEXT, TEXT, TEXT, TEXT) IS
$qq$
Purpose: Transfers the rows from "transit_tmp" to "core_data_tables.assay_data". Assumes all FKs are already present so it can onmly be called once
the metadata is loaded and the "file_load_id" has been created. This ID is required to link the loaded data to its associated metadata.
The function "JSONB_OBJECT" performs the crucial task of creating the key-value pairs where the assay attribute names are keys for the assay values.
Returns the number of rows inserted
$qq$;


CREATE OR REPLACE FUNCTION client_procedures.load_data_batch(p_experiment_name TEXT,
                                                             p_assay_name TEXT,
                                                             p_username TEXT,
                                                             p_loaded_file_fullname TEXT,
                                                             p_assay_attribute_names TEXT,
                                                             p_assay_attribute_names_delimiter TEXT DEFAULT E'\t')
RETURNS JSONB
AS
$$
DECLARE
  l_result_summary TEXT;
  l_file_load_id TEXT;
  l_data_loaded_rowcount INTEGER;
BEGIN
  l_file_load_id := client_procedures.load_metadata(p_experiment_name,
                                                    p_assay_name,
                                                    p_username,
                                                    p_loaded_file_fullname,
                                                    p_assay_attribute_names);
  l_data_loaded_rowcount := client_procedures.load_assay_data(p_assay_attribute_names, p_experiment_name, l_file_load_id);
  TRUNCATE transit_tmp;
  l_result_summary := ('{"file_load_id": ' || '"' || l_file_load_id || '"' || 
    ', "data_loaded_rowcount": ' || l_data_loaded_rowcount || '}')::JSONB;
  RETURN l_result_summary;
END;
$$
LANGUAGE plpgsql
  SECURITY DEFINER;  
COMMENT ON FUNCTION client_procedures.load_data_batch(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) IS
$qq$
Purpose: Calls two functions to load metadata and data rows. To be called by client programs.
Returns a JSONB string that provides a load summary.
$qq$;


-- Prepopulate tables
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('viable_cells',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd4_mfi_cd137',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd4_mfi_proliferation',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd4_mfi_cd25',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd4_percent_proliferation',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd4_percent_cd25',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd4_percent_cd137',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd8_mfi_cd137',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd8_mfi_proliferation',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd8_mfi_cd25',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd8_percent_proliferation',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd8_percent_cd25',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd8_percent_cd137',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd4_cell_number',	'measurement',	'numeric',	'Add a description');
INSERT INTO core_data_tables.assay_attributes(assay_attribute_name, assay_attribute_type, assay_attribute_data_type, assay_attribute_description) VALUES('cd8_cell_number',	'measurement',	'numeric',	'Add a description');

INSERT INTO core_data_tables.assays(assay_name, assay_description) VALUES('Pan T cell assay', 'Give a detailed description here');