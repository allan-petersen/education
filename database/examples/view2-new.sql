/*
* The script encoding is UTF-8. Please remember to set: NLS_LANG=DANISH_DENMARK.UTF8
*
* TODO. Try to improve the performance of this view.
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
* null                                                                               Inactive sor_organizationunits with a providerIdentifier without active siblings, or sor_organizationunits wihtout a providerIdentifier
*
* NOTE. For a given sorIdentifier the value of the EPICPROVIDERINDENTIFIER column will not always match the SOR value.
* ============================================================================================================================
* The value of the PROVIDERINDENTIFIER column will match the SOR value.
*
* Multiple location codes for a providerIdentifier:
*    The sorIdentifier (of provider/clinic), locationNumber, name, address etc. will change in Epic according to the latest SOR update.
* Multiple clinics for a providerIdentifier:
*    The sorIdentifier (of provider/clinic), name, address etc. will change in Epic according to the latest SOR update.
* 
* NOTE, that the view does include inactive sor_organizationunits. It it a client responsibillty to handle these sor_organizationunits correctly.
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
   -- Find the sor_organizationunits having or inheriting a locationscode and having children with a provideridentifier
   --
   -- Traverse the hierarchy buttom up.
   --
   -- Example: 
   -- select *
   -- from units_having_locationcode_and_child_with_pid
   -- where sorIdentifier in (
   -- 62821000016003,
   -- 62831000016001,
   -- 62841000016008,
   -- 62851000016006,
   -- 62861000016009,
   -- 62871000016004);
   --
   -- SORIDENTIFIER
   -- 62851000016006
   -- 62841000016008
   -- 62821000016003
   -- 62871000016004
   -- 62861000016009
   -- 62831000016001
   --
   units_having_locationcode_and_child_with_pid AS (
      SELECT DISTINCT sor.soridentifier
      FROM sororgunit_with_locationcode sor
      LEFT JOIN po_orgunitrelationship rel ON rel.orgunitchild = sor.organizationunit
      WHERE rel.organizationdimension = (SELECT sorDimension FROM dimension)
      START WITH sor.provideridentifier IN (SELECT provideridentifier FROM sororgunit_provideridnotnull)
      CONNECT BY PRIOR rel.orgunitparent = rel.orgunitchild
                 AND PRIOR rel.organizationdimension = rel.organizationdimension
   ), 
   --
   -- Find the locationCode, address and virtual address of a sorIdentifier
   --
   -- Received this part from René Bentzen. 
   --
   -- Example:
   -- select *
   -- from address_virtualaddress_location
   -- where sorIdentifier in (
   -- 62821000016003,
   -- 62831000016001,
   -- 62841000016008,
   -- 62851000016006,
   -- 62861000016009,
   -- 62871000016004);
   -- 
   -- SORLEVEL;POSTALADDRESS_ID;VIRTUALADDRESS_ID;INHERITEDEANLOCATIONNUMBER_ID;SORIDENTIFIER
   -- 1;113827;8784;8397;62821000016003
   -- 2;113827;8784;8397;62831000016001
   -- 3;113827;8784;8397;62851000016006
   -- 3;113827;8784;8397;62861000016009
   -- 3;113827;8784;8397;62871000016004
   -- 3;113827;8784;8397;62841000016008
   address_virtualaddress_location AS (
          SELECT LEVEL AS sorLevel,
          -- Own postal address, or first found up the tree
          nvl(CONNECT_BY_ROOT sor.postaladdress,
              TO_NUMBER(rtrim(
              substr(
                  ltrim(
                      sys_connect_by_path(sor.postaladdress, '|'),
                      '|'
                     ),
                     0,
                     instr(
                         ltrim(sys_connect_by_path(sor.postaladdress, '|')
                               || '|',
                               '|'),
                         '|',
                         1
                     )
                 ),
                 '|'
             ))) AS postaladdress_id,
             -- Own virtual address, or first found up the tree
             nvl(CONNECT_BY_ROOT sor.virtualaddress,
                 TO_NUMBER(rtrim(
                 substr(
                     ltrim(
                         sys_connect_by_path(sor.virtualaddress, '|'),
                         '|'
                     ),
                     0,
                     instr(
                         ltrim(sys_connect_by_path(sor.virtualaddress, '|')
                               || '|',
                               '|'),
                         '|',
                         1
                     )
                 ),
                 '|'
             ))) AS virtualaddress_id,
             -- If location number is to be inherited, then we look up the tree; otherwise, use its own
             CASE CONNECT_BY_ROOT sor.eanlocationinherited
                 WHEN '1' THEN
                     TO_NUMBER(rtrim(
                         substr(
                             ltrim(
                                 sys_connect_by_path(sor.eanlocation, '|'),
                                 '|'
                             ),
                             0,
                             instr(
                                 ltrim(sys_connect_by_path(sor.eanlocation, '|')
                                       || '|',
                                       '|'),
                                 '|',
                                 1
                             )
                         ),
                         '|'
                     ))
                 ELSE
                     CONNECT_BY_ROOT sor.eanlocation
             END                               AS inheritedeanlocationnumber_id,
             CONNECT_BY_ROOT sor.soridentifier AS soridentifier
         FROM
             po_orgunitrelationship rel
             LEFT JOIN sor_organizationunit   sor ON sor.organizationunit = rel.orgunitchild
             LEFT JOIN sor_organizationunit   sor_parent ON sor_parent.organizationunit = rel.orgunitparent
         WHERE
                 rel.organizationdimension = (
                     SELECT id FROM po_orgdimension WHERE name = 'SOROrgDimension'
                 )AND CONNECT_BY_ISLEAF = 1
            START WITH sor.soridentifier IN (
                 SELECT soridentifier FROM units_having_locationcode_and_child_with_pid
             )
             CONNECT BY PRIOR rel.orgunitparent = rel.orgunitchild
                    AND PRIOR rel.organizationdimension = rel.organizationdimension
	),				
   --
   -- Find the address
   --
   address AS (
      SELECT a.id,
      NVL2(a.id,
         a.streetname
         || NVL2(a.streetbuilding, ' ' || a.streetbuilding, '')
         || NVL2(a.floor, ' ' || a.floor, '')
         || NVL2(a.stairway, ' ' || a.stairway, '')
         || NVL2(a.suite, ' ' || a.suite, ''),
         NULL)           formattedaddresstext,
      a.postcode         postcodeidentifier,
      a.postdistrictname districtname
      FROM po_postaladdress a
   ),
   --
   -- Find the virtual address
   --
   virtualAddress AS (
      SELECT v.id,
         v.phonenumber      telephonenumberidentifier,
         v.faxnumber        faxnumberidentifier,
         v.emailaddress     emailaddressidentifier
      FROM sor_virtualaddress v
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
	 WHEN t.sourceEpicRegistration = 'unique' THEN t.parentName
     -- Set the collected names of the individual providers as Epic alias
     WHEN t.targetEpicRegistration = 'pidFromChild' THEN t.targetChildNames
	 WHEN t.sourceEpicRegistration = 'pidToParent' THEN t.parentName
     ELSE NULL
   END AS epicaliasnames,
   
   -- Set epic provideridentifier
   CASE 
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
      avl.sorLevel sorlevel,
      target_orgunit.providerIdentifier childProviderIdentifier,
      target_orgunit.targetEpicRegistration,
      source_orgunit.sourceEpicRegistration,
	  source_orgunit.siblingNames,
	  source_orgunit.activeSorIds, 
	  NVL(source_orgunit.numberOfActiveSorIds, 0) AS numberOfActiveSorIds, 
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
   JOIN address_virtualaddress_location avl ON avl.soridentifier = su.soridentifier
   JOIN sor_eanlocation e ON e.id = avl.inheritedeanlocationnumber_id
   LEFT JOIN parent_orgunit p ON p.soridentifier = su.soridentifier
   -- Without the extra AND clause on target_orgunit, sorIdentifier will not be unique
   LEFT JOIN target_orgunit ON target_orgunit.sorIdentifier = su.sorIdentifier AND (target_orgunit.providerIdentifier = su.providerIdentifier OR targetEpicRegistration = 'pidFromChild')
   LEFT JOIN source_orgunit ON source_orgunit.soridentifier = su.soridentifier
   LEFT JOIN address ON address.id = avl.postaladdress_id
   LEFT JOIN virtualAddress ON virtualAddress.ID = avl.virtualaddress_id
   ) 
   t;
 
-- TODO GRANT SELECT ON epic_sor_provider TO appl_read, appl_read1, cbas2spo;
