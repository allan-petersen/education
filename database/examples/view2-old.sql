/*
* The script encoding is UTF-8. Please remember to set: NLS_LANG=DANISH_DENMARK.UTF8
*
* This view contains the sorIdentifiers owning or inheriting a locationCode - with or without a providerIdentifier.
* See https://medcom.dk/wp-content/uploads/2025/03/Regelsaet-for-registrering-af-lokationsnumre-og-meddelelsestyper_final.pdf section 2.7
* Also see: https://svn.medcom.dk/svn/releases/Standarder/Syntaks%20og%20kommunikationsregler/XML/Dokumentation/synogkom.pdf
*
* The purpose of this view is to populate Epic with provider information from SOR.
* The view contains three levels: provider, clinic and location.
* Records sent to Epic must contain a unique providerIdentifier
*
* Due to SOR registration standards and Epic design mismatches, the view has to meet the following requrements:
*
* 1. sorIdentifier must be unique.
* 2. providerIndentifier must be unique.
* 3. locationCode is not unique.
*  
* The attributes EPICREGISTRATION, EPICPROVIDERINDENTIFIER and EPICALIASNAMES are populated according to the following table:
**
* EPICREGISTRATION          EPICPROVIDERINDENTIFIER          EPICALIASNAMES          REMARK
* pidToParent               null                             PID appended            PID is moved from the child level to the parent clinic level
* pidFromChild              PID                                                      PID set from the child level
* unique                    PID                                                      The providerIndentifer is unique
* unhandled                                                  PID appended            There is no way to make the providerIdentifer unique for these sor registrations
* null                                                                               Inactive sor_organizationunits with a providerIdentifier without active siblings or sor_organizationunits wihtout a providerIdentifier
*
* NOTE. For a given sorIdentifier the value of the EPICPROVIDERINDENTIFIER column will not always match, what you find in SOR.
* ============================================================================================================================
* The value of the PROVIDERINDENTIFIER column corresponds with SOR.
*
* Multiple locacation codes for a providerIdentifier. The integration will decide whether to set a providerIdentifier or not. 
* Multiple clinics for a providerIdentifier. The integration will decide whether to set a providerIdentifier or not. 
* Inactive. Inactive organization or inactive location code. The integration will decide whether to set a providerIdentifier or not. 
*
* Note, that the view does include inactive sor_organizationunits. It it a client responsibillty to handle these sor_organizationunits correctly.
*
* The epic_sor_provider view includes these SOR units having a provideridentifier or ancestors has a locationcode or inherits a locationcode. 
*
*/
CREATE OR REPLACE VIEW epic_sor_provider AS
   WITH dimension AS (
      SELECT id AS sorDimension FROM po_orgdimension WHERE name = 'SOROrgDimension'
   ),
   --
   -- Find the sor_organizationunits having a provideridentifier.
   --
   sororgunit_provideridnotnull AS (
      SELECT provideridentifier FROM sor_organizationunit WHERE provideridentifier IS NOT NULL
   ),
   --
   -- Find the sor_organizationunits having or inheriting a locationCode
   -- 
   sororgunit_with_locationcode AS (
          SELECT soridentifier, organizationunit, provideridentifier FROM sor_organizationunit WHERE (eanlocation IS NOT NULL OR eanlocationinherited = 1)
   ),
    -- 
   -- Find the sor_organizationunits leaf nodes of sor_organizationunits having a provideridentifier
   -- Only include sor_organizationunits having or inheriting a locationCode
   --
   -- Traverse the hierarchy buttom up.
   --
   -- Example: 
   -- select *
   -- from locationcode_leafs_of_has_providerid
   -- where soridentifier in (62821000016003, 62831000016001, 62851000016006);
   --
   -- SORIDENTIFIER
   -- 62821000016003;
   --
   locationcode_leafs_of_has_providerid AS (
      SELECT DISTINCT sor.soridentifier
      FROM sororgunit_with_locationcode sor
      LEFT JOIN po_orgunitrelationship rel ON rel.orgunitchild = sor.organizationunit
      WHERE rel.organizationdimension = (SELECT sorDimension FROM dimension)
	  AND CONNECT_BY_ISLEAF = 1  
      START WITH sor.provideridentifier IN (SELECT provideridentifier FROM sororgunit_provideridnotnull)
      CONNECT BY PRIOR rel.orgunitparent = rel.orgunitchild
                 AND PRIOR rel.organizationdimension = rel.organizationdimension
   ), 
   -- Find the locationCode for a sorIdentifier 
   -- 
   -- Traverse the hierarchy top down.
   -- Start with from locationcode_leafs_of_has_providerid.
   -- RootSorIdentifier. CONNECT_BY_ROOT to get root value
   -- SorIdentifier. The child sorIdentifier
   -- InheritedeLocationNumbeId. Sys_connect_by_path concatenates the values of the specified column from the root of the hierarchy to the current row).
   -- The result is a list of locationCodes.
   -- Next the last location code is extracted.
   --
   -- Example:
   -- select *
   -- from eanlocation_code
   -- where soridentifier in (62821000016003, 62831000016001, 62851000016006);
   --
   -- ROOTSORIDENTIFIER;SORIDENTIFIER;INHERITEDLOCATIONNUMBERID;SORLEVEL;ROWNUMBER
   -- 62821000016003;62821000016003;8397;1;1
   -- 62821000016003;62831000016001;8397;2;1
   -- 62821000016003;62851000016006;8397;3;1
   --
   -- select *
   -- from eanlocation_code
   -- where soridentifier = 1037051000016006;
   -- ROOTSORIDENTIFIER;SORIDENTIFIER;INHERITEDLOCATIONNUMBERID;SORLEVEL;ROWNUMBER
   -- 1420301000016002;1037051000016006;43305;3;1
   --
   eanlocation_code AS (
      -- Select the 1. row, when a parent and a child have the same locationCode defined (no inheritance).
      -- Example sorIdentifiers: 1037051000016006, 984261000016007, 1409001000016003
      --
      SELECT rootSoridentifier, sorIdentifier, inheritedLocationNumberId, sorLevel, rowNumber
      FROM (
         SELECT CONNECT_BY_ROOT sor.soridentifier AS rootSoridentifier, 
	     sor.soridentifier soridentifier,
         -- Extract the last non-NULL eanlocation from the path
         SUBSTR(
            -- Remove any leading/traling delimiters). Add a leading '|' to ensure that there is always a leading delimiter 
            '|' || RTRIM(LTRIM(SYS_CONNECT_BY_PATH(sor.eanlocation, '|')  , '|'),  '|' ),
            -- Find the position of the last occurrence of the delimiter ('|')
            INSTR(
               -- Remove any leading/traling delimiters. Add a leading '|' to ensure that there is always a leading delimiter 
              '|' || RTRIM(LTRIM(SYS_CONNECT_BY_PATH(sor.eanlocation, '|')  , '|'),  '|' ),
              '|', 
	          -1
            ) -- END INSTR. Locates the last occurrence of '|' starting from the end  
            + 1 -- Adjust the start position to the character immediately after the last '|'
         )
         AS inheritedLocationNumberId,
         LEVEL AS sorLevel,
         ROW_NUMBER() OVER (PARTITION BY sorIdentifier ORDER BY LEVEL DESC) AS rowNumber
         FROM sor_organizationunit sor 
         LEFT JOIN po_orgunitrelationship rel ON rel.orgunitchild = sor.organizationunit
         WHERE rel.organizationdimension = (SELECT sorDimension FROM dimension)
  	     AND (sor.eanlocation IS NOT NULL OR sor.eanlocationinherited = 1)
         START WITH sor.soridentifier IN (SELECT soridentifier FROM locationcode_leafs_of_has_providerid)
         CONNECT BY PRIOR rel.orgunitchild = rel.orgunitparent
                AND PRIOR rel.organizationdimension = rel.organizationdimension
         )       
      WHERE rowNumber = 1        
   ),
   --
   -- Find the sor_organizationunit having or inheriting an address or virtualAddress
   -- 
   sororgunit_with_address_or_virtualaddress AS (
          SELECT soridentifier, organizationunit, provideridentifier FROM sor_organizationunit WHERE (postaladdress IS NOT NULL OR postaladdressinherited = 1 OR virtualaddress IS NOT NULL OR virtualaddressinherited =1)
   ),
    -- 
   -- Find the sor_organizationunits leaf nodes of sor_organizationunits having a provideridentifier
   -- Only include sor_organizationunits having or inheriting an address/virtualAddress
   --
   -- Traverse the hierarchy buttom up.
   --
   -- Example: 
   -- select *
   -- from leafs_of_has_providerid
   -- where soridentifier in (62821000016003, 62831000016001, 62851000016006);
   --
   -- SORIDENTIFIER
   -- 62821000016003;
   --
   address_virtualaddress_leafs_of_has_providerid AS (
      SELECT DISTINCT sor.soridentifier
      FROM sororgunit_with_address_or_virtualaddress sor
      LEFT JOIN po_orgunitrelationship rel ON rel.orgunitchild = sor.organizationunit
      WHERE rel.organizationdimension = (SELECT sorDimension FROM dimension)
	  AND CONNECT_BY_ISLEAF = 1  
      START WITH sor.provideridentifier IN (SELECT provideridentifier FROM sororgunit_provideridnotnull)
      CONNECT BY PRIOR rel.orgunitparent = rel.orgunitchild
                 AND PRIOR rel.organizationdimension = rel.organizationdimension
   ), 
   -- Find the address and the virtualAddress for a sorIdentifier
   -- 
   -- Traverse the hierarchy top down.
   -- Start from address_virtualaddress_leafs_of_has_providerid
   -- Sys_connect_by_path concatenates the values of the specified column from the root of the hierarchy to the current row).
   -- The result is a list of postaladdress/virtualAddress.
   -- Next the last postaladdress/virtualAddress is extracted.
   --
   -- Example:
   -- select *
   -- from address_hierarchy
   -- where soridentifier in (62821000016003, 62831000016001, 62851000016006);
   -- 
   -- SORIDENTIFIER;POSTALADDRESSINHERITED;POSTALADDRESS;VIRTUALADDRESSINHERITED;VIRTUALADDRESS;INHERITEDPOSTALADDRESS;INHERITEDVIRTUALADDRESS;SORLEVEL;ROWNUMBER
   -- 62821000016003;0;113827;0;8784;113827;8784;1;1
   -- 62831000016001;1;;1;;113827;8784;2;1
   -- 62851000016006;1;;1;;113827;8784;3;1
   -- 
   address_hierarchy AS (
      -- Select the 1. row, when a parent and a child have the same postalAddress/virtualAddress defined (no inheritance).
      SELECT soridentifier, postaladdressinherited, postaladdress, virtualaddressinherited, virtualaddress, inheritedPostalAddress, inheritedVirtualAddress, sorLevel, rowNumber
	  FROM (
         SELECT sor.soridentifier AS soridentifier, sor.postaladdressinherited, sor.postaladdress, sor.virtualaddressinherited, sor.virtualaddress,
	     --
	     -- Extract the last non-NULL postalAddress from the path
	     -- 
         SUBSTR(
            -- Remove any leading/traling delimiters). Add a leading '|' to ensure that there is always a leading delimiter 
            '|' || RTRIM(LTRIM(SYS_CONNECT_BY_PATH(sor.postaladdress, '|')  , '|'),  '|' ),
            -- Find the position of the last occurrence of the delimiter ('|')
            INSTR(
               -- Remove any leading/traling delimiters. Add a leading '|' to ensure that there is always a leading delimiter 
              '|' || RTRIM(LTRIM(SYS_CONNECT_BY_PATH(sor.postaladdress, '|')  , '|'),  '|' ),
              '|', 
	          -1
            ) -- END INSTR. Locates the last occurrence of '|' starting from the end  
            + 1 -- Adjust the start position to the character immediately after the last '|'
         )
         AS inheritedPostalAddress,
	     --
	     -- Extract the last non-NULL virtualaddress from the path
	     --
         SUBSTR(
            -- Remove any leading/traling delimiters). Add a leading '|' to ensure that there is always a leading delimiter 
            '|' || RTRIM(LTRIM(SYS_CONNECT_BY_PATH(sor.virtualaddress, '|')  , '|'),  '|' ),
            -- Find the position of the last occurrence of the delimiter ('|')
            INSTR(
               -- Remove any leading/traling delimiters. Add a leading '|' to ensure that there is always a leading delimiter 
              '|' || RTRIM(LTRIM(SYS_CONNECT_BY_PATH(sor.virtualaddress, '|')  , '|'),  '|' ),
              '|', 
	          -1
            ) -- END INSTR. Locates the last occurrence of '|' starting from the end  
            + 1 -- Adjust the start position to the character immediately after the last '|'
         )
         AS inheritedVirtualAddress,
	     LEVEL AS sorLevel,
         ROW_NUMBER() OVER (PARTITION BY sorIdentifier ORDER BY LEVEL DESC) AS rowNumber
         FROM sor_organizationunit sor
         JOIN po_orgunitrelationship rel ON sor.organizationunit = rel.orgunitchild
         WHERE rel.organizationdimension = (SELECT sorDimension FROM dimension)
         START WITH sor.soridentifier IN (SELECT soridentifier FROM address_virtualaddress_leafs_of_has_providerid)
         CONNECT BY PRIOR rel.orgunitchild = rel.orgunitparent
                AND PRIOR rel.organizationdimension = rel.organizationdimension
         )
      WHERE rowNumber = 1        	  
   ),
   --
   -- Find the address
   --
   address AS (
      SELECT h.soridentifier,
      NVL2(a.id,
         a.streetname
         || NVL2(a.streetbuilding, ' ' || a.streetbuilding, '')
         || NVL2(a.floor, ' ' || a.floor, '')
         || NVL2(a.stairway, ' ' || a.stairway, '')
         || NVL2(a.suite, ' ' || a.suite, ''),
         NULL)           formattedaddresstext,
      a.postcode         postcodeidentifier,
      a.postdistrictname districtname
      FROM address_hierarchy h
      JOIN po_postaladdress a ON a.id = h.inheritedPostalAddress
	  WHERE (h.postaladdress IS NOT NULL OR h.postaladdressinherited = 1)
   ),
   --
   -- Find the virtual address
   --
   virtualAddress AS (
      SELECT h.soridentifier,
         v.phonenumber      telephonenumberidentifier,
         v.faxnumber        faxnumberidentifier,
         v.emailaddress     emailaddressidentifier
      FROM address_hierarchy h
      JOIN sor_virtualaddress v ON v.id = h.inheritedVirtualAddress
	  WHERE (h.virtualaddress IS NOT NULL OR h.virtualaddressinherited = 1)
   ),
   -- 
   -- location_base select 
   --
   -- Example:
   -- select *
   -- from location_base
   -- where locproviderIdentifier = 090263;
   --
   -- LOCATION;LOCPROVIDERIDENTIFIER;UPDATED
   -- 5790002269813;090263;2024-06-27 07:08:08
   -- 5790002762888;090263;2025-05-16 07:04:49
   -- 5790002762901;090263;2025-05-16 06:53:37
   -- 5790002762338;090263;2025-05-01 06:41:36
   --
   location_base AS (
     SELECT ean.locationcode AS location, sor.provideridentifier AS locprovideridentifier, ean.updated
            FROM eanlocation_code
            JOIN sor_organizationunit sor ON sor.soridentifier = eanlocation_code.soridentifier
            JOIN sor_eanlocation ean ON ean.id = eanlocation_code.inheritedlocationnumberid
		    -- Active sor_organizationunit
		     AND sysdate BETWEEN NVL(sor.startdate, sysdate) AND NVL(sor.enddate, sysdate)
            -- Active location code
            AND sysdate BETWEEN NVL(ean.startdate, sysdate) AND NVL(ean.enddate, sysdate) AND ean.nonactive = 0
   ),
   --
   -- Find the number active of locations grouped by active provideridentifier.
   -- 
   -- Example:
   -- select *
   -- from locations 
   -- where providerIdentifier = 090263;
   --
   -- NUMBEROFLOCATIONS;PROVIDERIDENTIFIER
   -- 4;090263
   --
   locations AS (
      SELECT COUNT(location) AS numberoflocations,
      -- Using LISTAGG returns ORA-01489: result of string concatenation is too long
      -- LISTAGG(location, ',') WITHIN GROUP(ORDER BY location) AS locationlist,
      -- Performance?
      -- RTRIM(XMLAGG(XMLELEMENT(e, location || ',') ORDER BY location).EXTRACT('//text()').getClobVal(), ',') AS locationlist,
      MAX(locprovideridentifier) AS provideridentifier
      FROM(
	     SELECT DISTINCT location, locprovideridentifier FROM location_base
      ) t
      GROUP BY locProviderIdentifier
   ),
   --
   -- Find the latest updated location code for a providerIdentifier. 
   --
   -- In case of multiple active locations for a providerIdentifier, this select is used for selecting the locationCode getting the provideridentifier in Epic.  
   --
   -- Example:
   -- select *
   -- from latest_location 
   -- where providerIdentifier = 090263;
   --
   -- LATESTUPDATEDLOCATION;PROVIDERIDENTIFIER
   -- 5790002762888;090263
   --
   -- 
   latest_location AS (
      SELECT location AS latestUpdatedLocation,
      locprovideridentifier AS provideridentifier
	  FROM (
	     SELECT location, locprovideridentifier,
         ROW_NUMBER() OVER (PARTITION BY locprovideridentifier ORDER BY updated DESC, location DESC) AS rowNumber
         FROM location_base
	  )
      WHERE rowNumber = 1
    ),
   -- 
   -- clinic_base select 
   --
   -- Example.
   -- select *
   -- from clinic_base
   -- where provideridentifier = 400033;
   -- 
   -- CLINICSORID;CHILDPROVIDERIDENTIFIER;UPDATED
   -- 656241000016005;400033;2024-07-12 09:46:16
   -- 936091000016006;400033;2024-07-12 09:46:17
   -- 936111000016003;400033;2024-07-12 09:46:17
   -- 1205801000016008;400033;2024-07-12 09:46:18
   --
   clinic_base AS (
       SELECT clinic.sorIdentifier AS clinicSorId, provider.provideridentifier AS childProviderIdentifier, clinic.updated
           FROM eanlocation_code
           JOIN sor_organizationunit clinic ON clinic.soridentifier = eanlocation_code.soridentifier
           JOIN po_orgunitrelationship rel ON rel.orgunitparent = clinic.organizationunit
           JOIN sor_organizationunit provider ON provider.organizationunit = rel.orgunitchild
		   JOIN sor_eanlocation ean ON ean.id = eanlocation_code.inheritedlocationnumberid
           WHERE rel.organizationdimension = (SELECT sordimension FROM dimension)
           -- Active location code
           AND sysdate BETWEEN NVL(ean.startdate, sysdate) AND NVL(ean.enddate, sysdate)
           AND ean.nonactive = 0
			-- Active sor_organizationunit
		   AND sysdate BETWEEN NVL(provider.startdate, sysdate) AND NVL(provider.enddate, sysdate)
		   -- providerIdentifer must have a locationcode 
		   AND provider.eanlocationinherited = 1
           -- Active clinics
           AND sysdate BETWEEN NVL(clinic.startdate, sysdate) AND NVL(clinic.enddate, sysdate)
   ),
   --
   -- Find the number of active clinics grouped by active provideridentifier.
   --
   -- Example.
   -- select *
   -- from clinics
   -- where provideridentifier = 400033;
   -- 
   -- NUMBEROFCLINICS;PROVIDERIDENTIFIER
   -- 4;400033
   --
   clinics AS (
      SELECT COUNT(DISTINCT clinicSorId) AS numberOfClinics,
         -- Using LISTAGG returns ORA-01489: result of string concatenation is too long
         -- LISTAGG(clinicSorId, ',') WITHIN GROUP(ORDER BY clinicSorId) AS clinicList,
         -- Performance?
         -- RTRIM(XMLAGG(XMLELEMENT(e, clinicSorId || ',') ORDER BY clinicSorId).EXTRACT('//text()').getClobVal(), ',') AS clinicList,
         MAX(childProviderIdentifier) AS providerIdentifier
         FROM (
		   SELECT DISTINCT clinicSorId, childProviderIdentifier from clinic_base
         ) t
         GROUP BY childProviderIdentifier
   ),
   --
   -- Find the latest updated clinic.
   --
   -- In case of multiple active clinics for a providerIdentifier, this select is used for selecting the clinic sorIdentifier getting the provideridentifier in Epic.  
   --
   -- Example.
   -- select *
   -- from latest_clinic
   -- where provideridentifier = 400033;
   -- 
   -- LATESTUPDATEDCLINIC;PROVIDERIDENTIFIER
   --1205801000016008;400033
   --
   latest_clinic AS (
      SELECT clinicSorId AS latestUpdatedClinic,
      childProviderIdentifier AS provideridentifier
	  FROM (
	     SELECT clinicSorId, childProviderIdentifier,
         ROW_NUMBER() OVER (PARTITION BY CHILDPROVIDERIDENTIFIER ORDER BY UPDATED DESC, CLINICSORID DESC) AS rowNumber
         FROM clinic_base
	  )
      WHERE rowNumber = 1
   ),
   --
   -- Find the number of active children for a parent sorIdentifier grouped by providerIdentifier
   --
   -- Example:
   --
   -- select *
   -- from number_of_children
   -- where soridentifier = 1209531000016004;
   --
   -- SORIDENTIFIER;PROVIDERIDENTIFIER;NUMBEROFCHILDREN;CHILDNAMES;ACTIVESORIDS
   -- 1209531000016004;507504;1;Line Schouw Jensen;1381811000016003
   -- 1209531000016004;959812;1;Victor Moblet;1381801000016000
   -- 1209531000016004;968536;9;Alexander Holm Petersen¤Dorte Agerholm Hansen¤Filip Hansen¤Jacob Juel Høiby¤Lucas Håkansson¤Marta Kempf¤Melina Iversen¤Mia Troelsen¤Thomas Lauersen;1381781000016001¤1383051000016009¤1383061000016007¤1383071000016002¤1383081000016000¤1385241000016000¤1385261000016004¤1515381000016000¤1557631000016009
   --
   number_of_children AS (
     SELECT parent.sorIdentifier sorIdentifier, child.providerIdentifier, COUNT(*) AS numberOfChildren, 
	 LISTAGG(child.entityname, '¤') WITHIN GROUP(ORDER BY child.entityname) childNames,
	 LISTAGG(child.sorIdentifier, '¤') WITHIN GROUP(ORDER BY child.sorIdentifier) activeSorIds
     FROM sor_organizationunit parent
     JOIN po_orgunitrelationship rel ON rel.orgunitparent = parent.organizationunit 
     JOIN sor_organizationunit child ON child.organizationunit = rel.orgunitchild 
     -- 
     -- Unable to require that the parent  must have a provideridentifier.
     -- Example: Soridentifier 5790000223435 (Municipality unit) has a providerIndentifier and a child with a providerIndentifier. 
     -- WHERE parent.provideridentifier IS NULL
     -- 
     -- Avoid problems where parent and child have the same providerIdentifier.
	 -- In this case the view will only include the parent sorIdentifier to avoid providerIndetifier duplicates.
     -- Example providerIdentifiers: 582077, 060348, 905965, 906785
     WHERE NVL(parent.providerIdentifier, 1) != NVL(child.providerIdentifier, 2)
     --      
     -- Sometimes the locationCode is set on the clinic. This is the reason for not having a  "AND parent.eanlocation IS NULL" clause
     -- 
	 -- Consider only active children to avoid, that the number of inactive providers for a certain providerIdentifier exceeds the number of active providers for another providerIdentifier.
	 -- In that case the providerIdentifier with the active providers would not be handled. See the rank_children statement below.
	 -- Active children. 
     AND sysdate BETWEEN NVL(child.startdate, sysdate) AND NVL(child.enddate, sysdate) 
     -- Only children having a provideridentifier is of interrest
     AND child.providerIdentifier IS NOT NULL
     GROUP BY parent.sorIdentifier, child.providerIdentifier
   ),
   --
   -- Rank the children 
   -- 
   -- Rank the groups in descending order by number of children
   -- We use ROW_NUMBER() OVER (ORDER BY cnt DESC, PID)  (and by PID to break ties). Only the first such group with maximum count will be given the move2parent action.
   --
   -- Example:
   -- select *
   -- from rank_children
   -- where soridentifier = 1209531000016004;
   --
   -- SORIDENTIFIER;PROVIDERIDENTIFIER;NUMBEROFCHILDREN;RN
   -- 1209531000016004;968536;9;1
   -- 1209531000016004;507504;1;2
   -- 1209531000016004;959812;1;3
   --
   rank_children AS (
      SELECT sorIdentifier, providerIdentifier, numberOfChildren,
      -- PARTITION BY. The row numbers will restart at 1
      -- If two or more rows have equal "numberOfChildren", they will then be sorted based on the "providerIdentifier" column
      ROW_NUMBER() OVER (PARTITION BY sorIdentifier ORDER BY numberOfChildren DESC, providerIdentifier) AS rn
      FROM number_of_children
   ),
   --
   -- Find my children distributed by providerIdentifier and set the epicRegistration to:
   -- pidFromChild: For the first providerIdentifier having the most children.
   -- unique: For all providerIdentifiers having 1 child.
   -- unhandled: For the rest of the providerIdentifiers - including other providerIdentifiers having the most children.
   --  
   -- Note, that the epicRegistration value is always set based on the active sor_organizationunits for the providerIdentifier in question.
   --  
   -- Example 1:
   -- select *
   -- from epic_registration
   -- where soridentifier = 1209531000016004;
   --
   -- SORIDENTIFIER;PROVIDERIDENTIFIER;NUMBEROFCHILDREN;ACTIVESORIDS;EPICREGISTRATION;CHILDNAMES
   -- 1209531000016004;507504;1;1381811000016003;unique;Line Schouw Jensen
   -- 1209531000016004;959812;1;1381801000016000;unique;Victor Moblet
   -- 1209531000016004;968536;9;1381781000016001¤1383051000016009¤1383061000016007¤1383071000016002¤1383081000016000¤1385241000016000¤1385261000016004¤1515381000016000¤1557631000016009;pidToParent;Alexander Holm Petersen¤Dorte Agerholm Hansen¤Filip Hansen¤Jacob Juel Høiby¤Lucas Håkansson¤Marta Kempf¤Melina Iversen¤Mia Troelsen¤Thomas Lauersen
   --
   -- Example 2:
   -- select *
   -- from epic_registration
   -- where soridentifier = 166651000016004;
   --
   -- SORIDENTIFIER;PROVIDERIDENTIFIER;NUMBEROFCHILDREN;ACTIVESORIDS;EPICREGISTRATION;CHILDNAMES
   -- 166651000016004;502057;1;166701000016005;unique;Tue Flader
   -- 166651000016004;502081;2;166661000016001¤1030031000016000;unhandled;Jette Wos¤Maja Jørgensen
   -- 166651000016004;502111;3;166681000016008¤935861000016000¤1030011000016006;pidToParent;Lars Bruun Christensen¤Laurits Terp¤Thea Esager Ørskov
   -- 166651000016004;502170;1;166721000016003;unique;Lone Frandsen
   -- 166651000016004;502197;2;166731000016001¤1030021000016002;unhandled;Steffen Korsbek Juul¤Thomas Vibberstoft
   -- 166651000016004;503053;2;166741000016008¤935831000016008;unhandled;Kristine G. Nielsen¤Mads Gustav Guldbrandsen
   -- 166651000016004;504963;2;341501000016006¤1073111000016003;unhandled;Christian Kock-Nielsen¤Kasper Svendsen
   --
   epic_registration AS (
      SELECT c.sorIdentifier, c.providerIdentifier, c.numberOfChildren, c.activeSorIds,
      CASE
         WHEN c.numberOfChildren = 1 THEN 'unique'
         WHEN c.numberOfChildren > 1 AND rn = 1 THEN 'pidToParent'
         ELSE 'unhandled'
         END AS epicRegistration,
         c.childNames
      FROM number_of_children c
      JOIN rank_children ON rank_children.sorIdentifier = c.sorIdentifier AND rank_children.provideridentifier = c.providerIdentifier
   ),
   -- Determine how to register in Epic by examining my children.
   -- Should this sor_organizationunit in Epic have the providerIndentifier set from the child sor_organizationunits?
   --
   -- Find the providerIdentifier distribution for my children. 
   -- See epic_registration.
   -- Set targetEpicRegistration to 'pidFromChild', when epicRegistration = 'pidToParent' 
   --
   -- Example:
   -- 
   -- select *
   -- from target_orgunit
   -- where soridentifier = 1209531000016004 and providerIdentifier = 968536;
   --
   -- SORIDENTIFIER;PROVIDERIDENTIFIER;NUMBEROFCHILDREN;TARGETEPICREGISTRATION;CHILDPROVIDERIDENTIFIER;CHILDNAMES
   -- 1209531000016004;968536;9;pidFromChild;968536;Alexander Holm Petersen¤Dorte Agerholm Hansen¤Filip Hansen¤Jacob Juel Høiby¤Lucas Håkansson¤Marta Kempf¤Melina Iversen¤Mia Troelsen¤Thomas Lauersen
   --
   target_orgunit AS (
      SELECT epic_registration.sorIdentifier, epic_registration.providerIdentifier, epic_registration.numberOfChildren,
         CASE WHEN epic_registration.epicRegistration = 'pidToParent' THEN 'pidFromChild' 
         ELSE epic_registration.epicRegistration 
         END AS targetEpicRegistration, 
         epic_registration.providerIdentifier AS childProviderIdentifier, 
		 epic_registration.childNames
      FROM epic_registration 
   ),
   -- Determine how to register in Epic by examining me and my siblings.
   -- Should this sor_organizationunit in Epic have the providerIndentifier moved to the parent sor_organizationunit?
   --
   -- Find the providerIdentifier distribution for me and my children. 
   -- See epic_registration.
   --
   -- Example
   -- select *
   -- from source_orgunit
   -- where soridentifier = 1515381000016000;
   --
   -- SORIDENTIFIER;SOURCEEPICREGISTRATION;ACTIVESORIDS;NUMBEROFACTIVESORIDS;SIBLINGNAMES
   -- 1515381000016000;pidToParent;1381781000016001¤1383051000016009¤1383061000016007¤1383071000016002¤1383081000016000¤1385241000016000¤1385261000016004¤1515381000016000¤1557631000016009;9;Alexander Holm Petersen¤Dorte Agerholm Hansen¤Filip Hansen¤Jacob Juel Høiby¤Lucas Håkansson¤Marta Kempf¤Melina Iversen¤Mia Troelsen¤Thomas Lauersen
   --
   source_orgunit AS (
      SELECT child.sorIdentifier, 
	  epicRegistration AS sourceEpicRegistration,
      epic_registration.activeSorIds, epic_registration.numberOfChildren AS numberOfActiveSorIds, 
      -- List af names for my siblings and myself
      epic_registration.childNames AS siblingNames
      FROM sor_organizationunit child
      JOIN po_orgunitrelationship rel ON rel.orgunitchild = child.organizationunit 
      JOIN sor_organizationunit parent ON parent.organizationunit = rel.orgunitparent 
      JOIN epic_registration ON epic_registration.sorIdentifier = parent.sorIdentifier 
      AND  epic_registration.providerIdentifier = child.providerIdentifier
   ),
   --
   -- Find the parent name for an organization
   -- Cannot use source_orgunit, since only active children are considered
   --
   -- Example:
   -- SELECT *
   -- FROM parent_orgunit
   -- WHERE soridentifier = 544791000016005;
   --
   -- SORIDENTIFIER;PARENTSORIDENTIFIER;PARENTNAME
   -- 544791000016005;19091000016002;Lægehuset i Borup
   --
   parent_orgunit AS (
      SELECT child.sorIdentifier, parent.sorIdentifier AS parentSorIdentifier, parent.entityName AS parentName
      FROM sor_organizationunit child
      JOIN po_orgunitrelationship rel ON rel.orgunitchild = child.organizationunit 
      JOIN sor_organizationunit parent ON parent.organizationunit = rel.orgunitparent 
   )
--
-- Add the calculated attributes epicaliasnames, epicprovideridentifier, epicRegistration to the view
--
SELECT 
  t.sorlevel,

  -- Set epic aliasnames
  CASE 
	 -- Add the parents name as alias
	 WHEN t.sourceEpicRegistration = 'unique' THEN LTRIM(t.aliasnames || '¤'|| t.parentName, '¤')
     -- Set the collected names of the individual providers as Epic alias
     WHEN t.targetEpicRegistration = 'pidFromChild' THEN t.targetChildNames
	 WHEN t.sourceEpicRegistration = 'pidToParent' THEN t.parentName
     ELSE NULL
   END AS epicaliasnames,
   
   -- Set epic provideridentifier
   CASE 
      -- Multiple locacation codes. The integration will decide whether to set a providerIdentifier or not. 
	  -- Multiple clinics. The integration will decide whether to set a providerIdentifier or not. 
	  --
      -- Avoid overwriting an existing providerIdentifier 
      WHEN t.targetEpicRegistration = 'pidFromChild' THEN NVL(t.providerIdentifier, t.childProviderIdentifier)
      WHEN t.sourceEpicRegistration = 'pidToParent' THEN NULL
      WHEN t.sourceEpicRegistration = 'unique' THEN t.provideridentifier 
      WHEN t.sourceEpicRegistration = 'unhandled' THEN NULL 
	  ELSE t.provideridentifier
   END AS epicprovideridentifier,

   -- Set epicRegistration
   CASE
      WHEN t.targetEpicRegistration = 'pidFromChild' THEN  t.targetEpicRegistration ELSE t.sourceEpicRegistration
   END AS epicRegistration,
   
   t.isActive,
   t.islocationCodeActive,
   t.provideridentifier, 
   t.soridentifier, 
   t.locationcode,
   t.entityname,
   t.aliasnames,
   t.sortype_systemid,
   t.sortype_classificationid,
   t.startDate,
   t.enddate,
   t.updated,
   t.locationStartdate,
   t.locationEnddate,
   t.locationUpdated,
   t.locationNonactive,
   t.parentSorIdentifier,
   t.parentName,
   t.siblingNames,
   t.activeSorIds, 
   t.numberOfActiveSorIds, 
   t.numberOfLocations,
   t.latestUpdatedLocation,
   t.numberOfClinics, 
   t.latestUpdatedClinic,
   t.formattedaddresstext,
   t.postcodeidentifier,
   t.districtname,
   t.telephonenumberidentifier,
   t.faxnumberidentifier,
   t.emailaddressidentifier,
   t.locationCodeInherited,
   t.postalAddressInherited,
   t.virtualaddressInherited
  
FROM (
   --
   -- The main select
   --
   SELECT 
      su.soridentifier soridentifier,
      su.provideridentifier provideridentifier,
	  -- The name of the individual providers should be prefixed with the name of the parent unit  
      CASE WHEN su.providerIdentifier IS NOT NULL THEN p.parentName || ' (' || su.entityname || ')' ELSE su.entityname END entityname,
      su.sortype_systemid,
      su.sortype_classificationid,
      su.sorfirstfromdate startDate,
      su.enddate endDate,
      su.updated updated, 
      e.locationcode AS locationcode,
	  e.startDate AS locationStartDate,
	  e.enddate AS locationEndDate,
	  e.nonactive AS locationNonactive,
	  e.updated AS locationUpdated,
      CASE WHEN locationSorOrg.entityname != su.entityname THEN locationSorOrg.entityname ELSE null END aliasnames,
      ean.sorLevel sorlevel,
      target_orgunit.providerIdentifier childProviderIdentifier,
      target_orgunit.targetEpicRegistration,
      source_orgunit.sourceEpicRegistration,
	  source_orgunit.siblingNames,
	  source_orgunit.activeSorIds, 
	  NVL(source_orgunit.numberOfActiveSorIds, 0) AS numberOfActiveSorIds, 
      NVL(locations.numberOfLocations, 0) AS numberOfLocations,
      latest_location.latestUpdatedLocation AS latestUpdatedLocation,
      NVL(clinics.numberOfClinics, 0) AS numberOfClinics,
      latest_clinic.latestUpdatedClinic AS latestUpdatedClinic,
	  p.parentSorIdentifier,
	  p.parentName,
      address.formattedaddresstext AS formattedaddresstext,
      address.postcodeidentifier AS postcodeidentifier,
      address.districtname AS districtname,
      virtualAddress.telephonenumberidentifier AS telephonenumberidentifier,
      virtualAddress.faxnumberIdentifier AS faxnumberIdentifier,
      virtualAddress.emailaddressIdentifier AS emailaddressIdentifier,
	  target_orgunit.childNames AS targetChildNames,
	  -- Active sor_organizationunit
      CASE WHEN sysdate BETWEEN NVL(su.startdate, sysdate) AND NVL(su.enddate, sysdate) THEN 1 ELSE 0 END AS isActive,
	  -- Active sor_eanlocation 
	  CASE WHEN sysdate BETWEEN NVL(e.startdate, sysdate) AND NVL(e.enddate, sysdate) AND e.nonactive = 0 THEN 1 ELSE 0 END AS isLocationCodeActive,
	  NVL(su.eanLocationInherited, 0) AS locationCodeInherited,
	  NVL(su.postalAddressInherited, 0) AS postalAddressInherited, 
	  NVL(su.virtualaddressInherited, 0) AS virtualaddressInherited
   FROM sor_organizationunit su
   JOIN eanlocation_code ean ON ean.soridentifier = su.soridentifier
   JOIN sor_eanlocation e ON e.id = ean.inheritedLocationNumberId
   JOIN sor_organizationunit locationSorOrg ON locationSorOrg.soridentifier = ean.soridentifier 
   LEFT JOIN parent_orgunit p ON p.soridentifier = su.soridentifier
   LEFT JOIN target_orgunit ON target_orgunit.sorIdentifier = su.sorIdentifier AND (target_orgunit.providerIdentifier = su.providerIdentifier OR targetEpicRegistration = 'pidFromChild')
   LEFT JOIN source_orgunit ON source_orgunit.soridentifier = su.soridentifier
   LEFT JOIN locations ON locations.providerIdentifier = su.providerIdentifier
   LEFT JOIN latest_location ON latest_location.providerIdentifier = su.providerIdentifier
   LEFT JOIN clinics ON clinics.providerIdentifier = su.providerIdentifier
   LEFT JOIN latest_clinic ON latest_clinic.providerIdentifier = su.providerIdentifier
   LEFT JOIN address ON address.soridentifier = su.soridentifier
   LEFT JOIN virtualAddress ON virtualAddress.soridentifier = su.soridentifier
   ) 
   t;
 
-- TODO GRANT SELECT ON epic_sor_provider TO appl_read, appl_read1, cbas2spo;
