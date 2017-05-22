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
