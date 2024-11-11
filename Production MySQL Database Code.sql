-- Create database
CREATE DATABASE IF NOT EXISTS centralized_forms_db;
USE centralized_forms_db;

-- Create form tracking table with Google Sheets specific fields
CREATE TABLE IF NOT EXISTS form_submissions (
    response_id VARCHAR(50) PRIMARY KEY,
    form_name VARCHAR(50),
    sheet_id VARCHAR(100),        -- Google Sheet ID
    tab_name VARCHAR(100),        -- Sheet tab name
    row_number INT,               -- Row in spreadsheet
    submission_date DATETIME,
    processing_status ENUM('pending', 'processed', 'error') DEFAULT 'pending',
    error_message TEXT,
    last_sync_timestamp DATETIME, -- Track last sync with Google Sheets
    
    INDEX idx_sheet (sheet_id, tab_name),
    INDEX idx_status (processing_status)
);

-- Core tables remain the same
CREATE TABLE IF NOT EXISTS Travelers (
    Traveler_ID INT AUTO_INCREMENT PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Email VARCHAR(100),
    Department VARCHAR(100),
    
    UNIQUE INDEX idx_email (Email),
    INDEX idx_department (Department)
);

CREATE TABLE IF NOT EXISTS Trip_Tracker (
    Trip_ID INT AUTO_INCREMENT PRIMARY KEY,
    Traveler_ID INT NOT NULL,
    Destination VARCHAR(255),
    Start_Date DATE,
    End_Date DATE,
    Purpose VARCHAR(255),
    
    FOREIGN KEY (Traveler_ID) REFERENCES Travelers(Traveler_ID),
    INDEX idx_dates (Start_Date, End_Date)
);

CREATE TABLE IF NOT EXISTS CSA (
    CSA_ID INT AUTO_INCREMENT PRIMARY KEY,
    Name VARCHAR(100),
    Department VARCHAR(100),
    Email VARCHAR(100),
    Date_Assigned DATE,
    
    INDEX idx_department (Department),
    INDEX idx_email (Email)
);

CREATE TABLE IF NOT EXISTS Incident (
    Incident_ID INT AUTO_INCREMENT PRIMARY KEY,
    CSA_ID INT,
    Incident_Type VARCHAR(100),
    Location VARCHAR(100),
    Date_Reported DATE,
    
    FOREIGN KEY (CSA_ID) REFERENCES CSA(CSA_ID),
    INDEX idx_type (Incident_Type),
    INDEX idx_date (Date_Reported)
);

CREATE TABLE IF NOT EXISTS Buildings (
    Building_ID INT AUTO_INCREMENT PRIMARY KEY,
    Name VARCHAR(100),
    Address VARCHAR(255),
    Total_Rooms INT,
    
    INDEX idx_name (Name)
);

CREATE TABLE IF NOT EXISTS Lease_Info (
    Lease_ID INT AUTO_INCREMENT PRIMARY KEY,
    Building_ID INT,
    Lease_Start_Date DATE,
    Lease_End_Date DATE,
    Status VARCHAR(50),
    
    FOREIGN KEY (Building_ID) REFERENCES Buildings(Building_ID),
    INDEX idx_dates (Lease_Start_Date, Lease_End_Date),
    INDEX idx_status (Status)
);

CREATE TABLE IF NOT EXISTS Central_Records (
    Record_ID INT AUTO_INCREMENT PRIMARY KEY,
    Traveler_ID INT,
    Trip_ID INT,
    CSA_ID INT,
    Incident_ID INT,
    Building_ID INT,
    Lease_ID INT,
    Record_Date DATE,
    Record_Type VARCHAR(50),
    
    FOREIGN KEY (Traveler_ID) REFERENCES Travelers(Traveler_ID),
    FOREIGN KEY (Trip_ID) REFERENCES Trip_Tracker(Trip_ID),
    FOREIGN KEY (CSA_ID) REFERENCES CSA(CSA_ID),
    FOREIGN KEY (Incident_ID) REFERENCES Incident(Incident_ID),
    FOREIGN KEY (Building_ID) REFERENCES Buildings(Building_ID),
    FOREIGN KEY (Lease_ID) REFERENCES Lease_Info(Lease_ID),
    
    INDEX idx_record_type (Record_Type),
    INDEX idx_record_date (Record_Date)
);

DELIMITER //

-- Process Travel Form Procedure
CREATE PROCEDURE process_travel_form(
    IN p_response_id VARCHAR(50),
    IN p_sheet_id VARCHAR(100),
    IN p_tab_name VARCHAR(100),
    IN p_row_number INT,
    IN p_name VARCHAR(100),
    IN p_email VARCHAR(100),
    IN p_department VARCHAR(100),
    IN p_destination VARCHAR(255),
    IN p_start_date DATE,
    IN p_end_date DATE,
    IN p_purpose VARCHAR(255)
)
BEGIN
    DECLARE v_traveler_id INT;
    DECLARE v_trip_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        UPDATE form_submissions 
        SET processing_status = 'error',
            error_message = 'Error processing travel form',
            last_sync_timestamp = NOW()
        WHERE response_id = p_response_id;
    END;

    START TRANSACTION;
    
    INSERT INTO form_submissions (
        response_id, form_name, sheet_id, tab_name, 
        row_number, submission_date, last_sync_timestamp
    )
    VALUES (
        p_response_id, 'travel_form', p_sheet_id, p_tab_name, 
        p_row_number, NOW(), NOW()
    );
    
    INSERT INTO Travelers (Name, Email, Department)
    VALUES (p_name, p_email, p_department)
    ON DUPLICATE KEY UPDATE
        Name = VALUES(Name),
        Department = VALUES(Department);
        
    SELECT Traveler_ID INTO v_traveler_id 
    FROM Travelers 
    WHERE Email = p_email;
    
    INSERT INTO Trip_Tracker (Traveler_ID, Destination, Start_Date, End_Date, Purpose)
    VALUES (v_traveler_id, p_destination, p_start_date, p_end_date, p_purpose);
    
    SET v_trip_id = LAST_INSERT_ID();
    
    INSERT INTO Central_Records (Traveler_ID, Trip_ID, Record_Date, Record_Type)
    VALUES (v_traveler_id, v_trip_id, CURDATE(), 'TRAVEL');
    
    UPDATE form_submissions 
    SET processing_status = 'processed',
        last_sync_timestamp = NOW()
    WHERE response_id = p_response_id;
    
    COMMIT;
END //

-- Process Building Form Procedure
CREATE PROCEDURE process_building_form(
    IN p_response_id VARCHAR(50),
    IN p_sheet_id VARCHAR(100),
    IN p_tab_name VARCHAR(100),
    IN p_row_number INT,
    IN p_name VARCHAR(100),
    IN p_address VARCHAR(255),
    IN p_total_rooms INT
)
BEGIN
    DECLARE v_building_id INT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        UPDATE form_submissions 
        SET processing_status = 'error',
            error_message = 'Error processing building form',
            last_sync_timestamp = NOW()
        WHERE response_id = p_response_id;
    END;

    START TRANSACTION;
    
    INSERT INTO form_submissions (
        response_id, form_name, sheet_id, tab_name, 
        row_number, submission_date, last_sync_timestamp
    )
    VALUES (
        p_response_id, 'building_form', p_sheet_id, p_tab_name, 
        p_row_number, NOW(), NOW()
    );
    
    INSERT INTO Buildings (Name, Address, Total_Rooms)
    VALUES (p_name, p_address, p_total_rooms);
    
    SET v_building_id = LAST_INSERT_ID();
    
    INSERT INTO Central_Records (Building_ID, Record_Date, Record_Type)
    VALUES (v_building_id, CURDATE(), 'BUILDING');
    
    UPDATE form_submissions 
    SET processing_status = 'processed',
        last_sync_timestamp = NOW()
    WHERE response_id = p_response_id;
    
    COMMIT;
END //

-- Process Incident Form Procedure
CREATE PROCEDURE process_incident_form(
    IN p_response_id VARCHAR(50),
    IN p_sheet_id VARCHAR(100),
    IN p_tab_name VARCHAR(100),
    IN p_row_number INT,
    IN p_csa_id INT,
    IN p_incident_type VARCHAR(100),
    IN p_location VARCHAR(100)
)
BEGIN
    DECLARE v_incident_id INT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        UPDATE form_submissions 
        SET processing_status = 'error',
            error_message = 'Error processing incident form',
            last_sync_timestamp = NOW()
        WHERE response_id = p_response_id;
    END;

    START TRANSACTION;
    
    IF NOT EXISTS (SELECT 1 FROM CSA WHERE CSA_ID = p_csa_id) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Invalid CSA_ID provided';
    END IF;
    
    INSERT INTO form_submissions (
        response_id, form_name, sheet_id, tab_name, 
        row_number, submission_date, last_sync_timestamp
    )
    VALUES (
        p_response_id, 'incident_form', p_sheet_id, p_tab_name, 
        p_row_number, NOW(), NOW()
    );
    
    INSERT INTO Incident (CSA_ID, Incident_Type, Location, Date_Reported)
    VALUES (p_csa_id, p_incident_type, p_location, CURDATE());
    
    SET v_incident_id = LAST_INSERT_ID();
    
    INSERT INTO Central_Records (CSA_ID, Incident_ID, Record_Date, Record_Type)
    VALUES (p_csa_id, v_incident_id, CURDATE(), 'INCIDENT');
    
    UPDATE form_submissions 
    SET processing_status = 'processed',
        last_sync_timestamp = NOW()
    WHERE response_id = p_response_id;
    
    COMMIT;
END //

DELIMITER ;