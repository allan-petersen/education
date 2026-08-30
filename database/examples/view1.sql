/*
* spo_provider view'et medtager de SOR enheder, der opfylder alle nedenstående betingelser:
*   Enheden har selv et ydernummer eller enheden har et/eller flere børn, der har et ydernummer.
*   Enheden har selv en lokationskode eller enheden nedarver en lokationskode.
*
*
* Scriptet er encoded i UTF-8, så husk: set NLS_LANG=DANISH_DENMARK.UTF8
*
*/
CREATE OR REPLACE VIEW spo_provider_new AS
   WITH 
   has_providerid_or_child_has_providerid_and_has_loc_or_inherits_loc AS (
      SELECT DISTINCT sor.soridentifier 
      FROM po_orgunitrelationship rel
      LEFT JOIN sor_organizationunit sor ON sor.organizationunit = rel.orgunitchild
      WHERE rel.organizationdimension = (SELECT id FROM po_orgdimension WHERE name = 'SOROrgDimension')
      AND (eanlocation IS NOT NULL OR eanlocationinherited = 1)
      START WITH
      sor.soridentifier IN (SELECT soridentifier FROM sor_organizationunit WHERE (provideridentifier IS NOT NULL))
      CONNECT BY PRIOR rel.orgunitparent = rel.orgunitchild
      AND PRIOR rel.organizationdimension = rel.organizationdimension
  ), 
   lookup AS (
     (SELECT soridentifier FROM has_providerid_or_child_has_providerid_and_has_loc_or_inherits_loc)
   ), 
    eanlocationcode AS (
       SELECT sor.soridentifier soridentifier,
       TO_NUMBER(rtrim(substr(ltrim(sys_connect_by_path(sor.eanlocation, '|'), '|'), 0, instr(ltrim(sys_connect_by_path(sor.eanlocation, '|') || '|', '|'), '|', 1)), '|')) inheritedeanlocationnumber_id,
       CONNECT_BY_ROOT sor.soridentifier AS childsoridentifier
       FROM po_orgunitrelationship rel
       LEFT JOIN sor_organizationunit sor ON sor.organizationunit = rel.orgunitchild
       WHERE rel.organizationdimension = (SELECT id FROM po_orgdimension WHERE name = 'SOROrgDimension')
       AND CONNECT_BY_ISLEAF = 1
       START WITH sor.soridentifier IN (SELECT soridentifier FROM lookup)
       CONNECT BY PRIOR rel.orgunitparent = rel.orgunitchild
       AND PRIOR rel.organizationdimension = rel.organizationdimension
   )
SELECT su.soridentifier soridentifier,
       su.provideridentifier provideridentifier,
       su.entityname entityname,
	   su.sorfirstfromdate startDate,
	   su.enddate endDate,
	   su.updated updated, 
	   CASE WHEN y.providerIdentifier is not null THEN 'SSIK' ELSE 'SOR' END entitySourceCode,
	   su.id entitySourceId,
       NVL(su.eanlocationinherited, 0) eanlocationinherited,
       e.locationcode eanlocationcode,
	   e.startDate eanlocationcodeStartDate,
	   e.enddate eanlocationcodeEndDate,
       e.nonactive locationnonactive,
	   e.updated eanupdated,
       CASE WHEN clinic.entityname != su.entityname THEN clinic.entityname ELSE null END aliasnames
FROM sor_organizationunit su
JOIN eanlocationcode ean ON (ean.childsoridentifier = su.soridentifier)
JOIN sor_eanlocation e ON e.id = ean.inheritedeanlocationnumber_id
JOIN sor_organizationunit clinic ON clinic.soridentifier = ean.soridentifier 
LEFT JOIN yder_provider y ON y.providerIdentifier = su.providerIdentifier;
 
-- TODO GRANT SELECT ON spo_provider TO appl_read, appl_read1, cbas2spo;
