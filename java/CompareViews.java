
package dk.regionh.integration.provider2Epic.compare;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import static dk.regionh.integration.provider2Epic.compare.CompareViews.Fields.*;
import static dk.regionh.integration.provider2Epic.compare.CompareViews.MapType.*;

/**
 * Compare spo_provider view and epic_sor_provider view contents.
 * Preparation
 * Note. The following queries limit on epicPproviderIdentifier/provideridentifier IS NOT NULL, since all units sent to EPic must have a providerIdentifier
 * 1a. Old view ACTIVE. SELECT soridentifier, entityname, provideridentifier, startdate, enddate, eanlocationcode, eanlocationcodestartdate, eanlocationcodeenddate, updated, eanupdated, aliasnames, entitysourcecode, '-' AS epicregistration, '-' AS isactive, '-' AS islocationcodeactive FROM spo_provider WHERE (enddate IS NULL OR enddate > sysdate) AND (eanlocationcodeenddate IS NULL OR eanlocationcodeenddate > sysdate) AND startdate < sysdate AND eanlocationcodestartdate < sysdate AND providerIdentifier IS NOT NULL;
 * 1b. Old view INACTIVE. SELECT soridentifier, entityname, provideridentifier, startdate, enddate, eanlocationcode, eanlocationcodestartdate, eanlocationcodeenddate, updated, eanupdated, aliasnames, entitysourcecode, '-' AS epicregistration, '-' AS isactive, '-' AS islocationcodeactive FROM spo_provider WHERE startDate > sysdate OR enddate < sysdate OR eanlocationcodestartdate > sysdate OR eanlocationcodeenddate < sysdate AND providerIdentifier IS NOT NULL;
 * 2. Export the spo_provider view result with separator ; and headers included in the file old.txt
 * 3a. New view ACTIVE. SELECT soridentifier, entityname, epicprovideridentifier, startdate, enddate, locationcode, locationstartdate, locationenddate, updated, locationupdated, epicaliasnames, '-' AS entitysourcecode, epicregistration, isactive, islocationcodeactive FROM epic_sor_provider WHERE isActive = 1 AND isLocationCodeActive = 1 AND epicProviderIdentifier IS NOT NULL;
 * 3b. New view INACTIVE. SELECT soridentifier, entityname, epicprovideridentifier, startdate, enddate, locationcode, locationstartdate, locationenddate, updated, locationupdated, epicaliasnames, '-' AS entitysourcecode, epicregistration, isactive, islocationcodeactive FROM epic_sor_provider WHERE (isActive = 0 OR isLocationCodeActive = 0) AND epicProviderIdentifier IS NOT NULL;
 * 4. Export the epic_sor_provider view result with separator ; and headers included in the file new.txt
 * 5. Copy the files old.txt, new.txt to src/test/resources/
 * 6. Run the CompareViews application.
 * 7. The compare result is saved to the src/test/resources/output.txt file.
 * 8. The output.txt file will contain:
 * 9.a A status column with one of the values:  IN_OLD, BOTH, IN_NEW
 * 9.b The values from the spo_provider view
 * 9.c The values from the epic_sor_provider view
 * 9.d The comparison result of the individual view values: EQUAL, NOT_EQUAL
 * 10. Import the output.txt into Excel and examine the result.
 */
@SpringBootApplication
public class CompareViews {

    private static final Logger LOG = LoggerFactory.getLogger(CompareViews.class);

    private static final String OLD_VIEW_FILENAME = "/prodOldActive3.txt";
    private static final String NEW_VIEW_FILENAME = "/prodNewActive3.txt";
    private static final String EQUAL = " equal";
    private static final String NOT_EQUAL = " not" + EQUAL;

    // Set SOR_PERSPECTIVE to true, if the compare result should contain all sorIdentifiers
    // When SOR_PERSPECTIVE is false, the compare result will not contain all sorIdentifiers,
    // but only the latest sorIdentifier (from the input files) for a given providerIdentifier
    private static final boolean SOR_PERSPECTIVE = false;

    enum Fields {
        SORIDENTIFIER,
        ENTITYNAME,
        PROVIDERIDENTIFIER,
        STARTDATE,
        ENDDATE,
        LOCATIONCODE,
        LOCATIONSTARTDATE,
        LOCATIONSENDDATE,
        UPDATED,
        LOCATIONUPDATED,
        EPICALIASNAMES,
        ENTITYSOURCECODE,
        EPICREGISTRATION,
        ISACTIVE,
        ISLOCATIONCODEACTIVE,
        ROW_STATUS,
        KEY_VALUE // The key used for a row. ProviderIdentifier or sorIdentifier
    }

    enum StatusType {
        IN_OLD, BOTH, IN_NEW
    }

    enum MapType {
        OLD, NEW, COMPARE, STATUS, KEY
    }

    /**
     * Map of key, maps,
     * where maps is a Map of MapType, simple map,
     * where simple map is a Map of <Fields, String>
     */
    final Map<String, Map<MapType, Map<Fields, String>>> result = new LinkedHashMap<>();

    private String oldHeader = null;

    private String newHeader = null;

    public static void main(String[] args) {
        if (args.length != 0) {
            System.out.println("Usage: java FileComparator");
            return;
        }
        LOG.info("Started");
        CompareViews compareViews = new CompareViews();
        compareViews.readOld(OLD_VIEW_FILENAME);
        compareViews.readNew(NEW_VIEW_FILENAME);
        compareViews.outputResult();
    }

    /**
     * Read the values from the old file
     *
     * @param fileName the filename
     */
    void readOld(final String fileName) {
        final InputStream inputStream = CompareViews.class.getResourceAsStream(fileName);
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream, StandardCharsets.UTF_8))) {
            String line;
            int lineNum = 1;
            while ((line = reader.readLine()) != null) {
                if (lineNum == 1) {
                    // Skip header line
                    oldHeader = line;
                    lineNum++;
                    continue;
                }
                Map<Fields, String> oldRow = populateRow(line);
                String key = getKey(oldRow);
                Map<MapType, Map<Fields, String>> maps = getMapsForKey(key);
                Map<Fields, String> statusMap = maps.get(STATUS);

                // Handle duplicate key
                if (SOR_PERSPECTIVE && StatusType.IN_OLD.toString().equals(statusMap.get(ROW_STATUS))) {
                    // Key already has status IN_OLD. Try to find an alternative key
                    key = getAlternateKey(key);
                }

                // Update OLD map
                maps = getMapsForKey(key);
                maps.put(OLD, oldRow);

                // Update STATUS map
                statusMap = maps.get(STATUS);
                statusMap.put(ROW_STATUS, StatusType.IN_OLD.toString());

                // Update key map
                Map<Fields, String> keyMap = maps.get(KEY);
                keyMap.put(KEY_VALUE, key);

                lineNum++;
            }

            System.out.println("Read number of lines " + --lineNum + " from file " + fileName);
        } catch (IOException e) {
            System.out.println("An error occurred while reading from the file: " + e.getMessage());
        }
    }

    /**
     * Read the values from the new file
     *
     * @param fileName the filename
     */
    void readNew(final String fileName) {
        final InputStream inputStream = CompareViews.class.getResourceAsStream(fileName);
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream, StandardCharsets.UTF_8))) {
            String line;
            int lineNum = 1;

            while ((line = reader.readLine()) != null) {
                if (lineNum == 1) {
                    newHeader = line;
                    // Skip header line
                    lineNum++;
                    continue;
                }
                Map<Fields, String> newRow = populateRow(line);
                String key = getKey(newRow);

                Map<MapType, Map<Fields, String>> maps = getMapsForKey(key);
                Map<Fields, String> statusMap = maps.get(STATUS);

                // Handle duplicate key
                if (SOR_PERSPECTIVE && StatusType.BOTH.toString().equals(statusMap.get(ROW_STATUS))) {
                    // Key already has status BOTH. Try to find an alternative key
                    key = getAlternateKey(key);
                }

                if (SOR_PERSPECTIVE && StatusType.IN_NEW.toString().equals(statusMap.get(ROW_STATUS))) {
                    // Key already has status IN_NEW. Try to find an alternative key
                    key = getAlternateKey(key);
                }

                // Update new MAP
                maps = getMapsForKey(key);
                maps.put(NEW, newRow);

                // Update STATUS map
                statusMap = maps.get(STATUS);
                if (StatusType.IN_OLD.toString().equals(statusMap.get(ROW_STATUS))) {
                    statusMap.put(ROW_STATUS, StatusType.BOTH.toString());
                // Keep status BOTH once set
                } else if (StatusType.BOTH.toString().equals(statusMap.get(ROW_STATUS))) {
                    statusMap.put(ROW_STATUS, StatusType.BOTH.toString());
                } else {
                    statusMap.put(ROW_STATUS, StatusType.IN_NEW.toString());
                }

                // Update key map
                Map<Fields, String> keyMap = maps.get(KEY);
                keyMap.put(KEY_VALUE, key);

                lineNum++;
            }
            System.out.println("Read number of lines " + --lineNum + " from file " + fileName);
        } catch (IOException e) {
            System.out.println("An error occurred while reading from the file: " + e.getMessage());
        }
    }

    /**
     * Create a map of fields from a file line
     *
     * @param line the line from the file
     * @return the Map of fields
     */
    Map<Fields, String> populateRow(final String line) {
        Map<Fields, String> row = new LinkedHashMap<>();
        final Integer[] i = {0};
        final Fields[] fields = Fields.values();
        // Split line, but include trailing empty strings
        final String[] lineFields = line.split(";", Fields.values().length);
        Arrays.stream(lineFields).forEach(field -> {
            row.put(fields[i[0]], lineFields[i[0]]);
            i[0] = i[0] + 1;
        });
        return row;
    }

    /**
     * Create an empty row
     *
     * @return the Map of fields
     */
    Map<Fields, String> createEmptyRow() {
        Map<Fields, String> row = new LinkedHashMap<>();
        final Fields[] fields = Fields.values();
        Arrays.stream(fields).filter(item -> !item.equals(ROW_STATUS) && !item.equals(KEY_VALUE)).forEach(field -> {
            row.put(field, "-");
        });
        return row;
    }

    /**
     * Create the result line for a key from the different maps
     *
     * @param key the key
     * @return the result line for the key
     */
    private String getResultLine(final String key) {
        Map<MapType, Map<Fields, String>> maps4Key = result.get(key);

        if (maps4Key.get(OLD).isEmpty()) {
            maps4Key.put(OLD, createEmptyRow());
        }
        if (maps4Key.get(NEW).isEmpty()) {
            maps4Key.put(NEW, createEmptyRow());
        }

        return Stream.of(maps4Key.get(STATUS), maps4Key.get(KEY), maps4Key.get(OLD), maps4Key.get(NEW), maps4Key.get(COMPARE))
                // For each of the four maps of the stream extract the values.
                // Make each collection of values a stream.
                // FlatMap flattens the individual streams into a single stream of String values.
                .flatMap(map -> map.values().stream())
                .collect(Collectors.joining(";"));
    }

    /**
     * Create the compare map for the key
     * Only key presents in both files will be compared
     *
     * @param key the key
     *
     */
    private void compareFields(String key) {
        Map<MapType, Map<Fields, String>> maps4Key = result.get(key);

        Map<Fields, String> oldMap = maps4Key.get(OLD);
        Map<Fields, String> newMap = maps4Key.get(NEW);
        Map<Fields, String> compareMap = maps4Key.get(COMPARE);
        Map<Fields, String> statusMap = maps4Key.get(STATUS);

        if (!StatusType.BOTH.toString().equals(statusMap.get(ROW_STATUS))) {
            Arrays.stream(Fields.values()).forEach(key1 -> {
                compareMap.put(key1, "-");
            });
        } else {
            Arrays.stream(Fields.values()).forEach(key1 -> {
                String oldValue = oldMap.get(key1);
                String newValue = newMap.get(key1);

                if (ROW_STATUS.equals(key1) || KEY_VALUE.equals(key1)) {
                    // Skip ROW_STATUS and KEY_VALUE fields in compare
                    ;
                } else if ((oldValue == null || oldValue.isEmpty()) && (newValue == null || newValue.isEmpty())) {
                    compareMap.put(key1, key1 + EQUAL);
                } else if (oldValue == null || oldValue.isEmpty()) {
                    compareMap.put(key1, key1 + NOT_EQUAL);
                } else if (newValue == null || newValue.isEmpty()) {
                    compareMap.put(key1, key1 + NOT_EQUAL);
                } else if (oldValue.stripLeading().stripTrailing().equalsIgnoreCase(newValue.stripLeading().stripTrailing())) {
                    compareMap.put(key1, key1 + EQUAL);
                } else {
                    compareMap.put(key1, key1 + NOT_EQUAL);
                }
            });
        }
    }

    /**
     * Write the result file
     */
    void outputResult() {
        try (BufferedWriter writer = new BufferedWriter(new FileWriter("src/test/resources/output.txt", StandardCharsets.ISO_8859_1))) {

            // Write headerLine
            writer.write(createHeaderLine());
            writer.newLine();

            result.keySet().forEach(key -> {
                        // Compare the key value and write the result to the COMPARE map
                        compareFields(key);
                        String resultLine = getResultLine(key);
                        try {
                            writer.write(resultLine);
                            writer.newLine();
                        } catch (IOException e) {
                            throw new RuntimeException(e);
                        }
                    }
            );
            System.out.println("File written successfully using BufferedWriter.");
        } catch (IOException e) {
            System.out.println("An error occurred while writing to the file: " + e.getMessage());
        }
    }

    boolean existingKey(final String key) {
        return result.get(key) != null;
    }

    /**
     * Get the maps for a specific key
     * Non-existing maps will be created
     */
    Map<MapType, Map<Fields, String>> getMapsForKey(final String key) {
        Map<MapType, Map<Fields, String>> maps = result.get(key);
        if (maps == null) {
            //  Create key
            maps = new LinkedHashMap<>();
            result.put(key, maps);
            if (maps.get(OLD) == null) {
                Map<Fields, String> oldMap = new LinkedHashMap<>();
                maps.put(OLD, oldMap);
            }
            if (maps.get(NEW) == null) {
                Map<Fields, String> oldMap = new LinkedHashMap<>();
                maps.put(NEW, oldMap);
            }
            if (maps.get(COMPARE) == null) {
                Map<Fields, String> oldMap = new LinkedHashMap<>();
                maps.put(COMPARE, oldMap);
            }
            if (maps.get(STATUS) == null) {
                Map<Fields, String> oldMap = new LinkedHashMap<>();
                maps.put(STATUS, oldMap);
            }
            if (maps.get(KEY) == null) {
                Map<Fields, String> keyMap = new LinkedHashMap<>();
                maps.put(KEY, keyMap);
            }
        }
        return maps;
    }

    /**
     * Get the key from a row
     * Use providerIdentifier as key. If providerIdentifier is not found use sorIdentifier as key.
     * <p>
     *
     * @param row the row
     * @return the key for the row
     */
    String getKey(Map<Fields, String> row) {
        final String providerIdentifier = row.get(PROVIDERIDENTIFIER);
        final String locationCode = row.get(LOCATIONCODE);
        final String sorÍdentifier = row.get(SORIDENTIFIER);

        String key = null;

        if (providerIdentifier != null && !providerIdentifier.isEmpty()) {
            key = providerIdentifier;
        } else {
            // ProviderIdentifier null
            if (sorÍdentifier != null && !sorÍdentifier.isEmpty()) {
                // New view: Location level, clinic level or epicRegistration = 'pidToParent'
                key = sorÍdentifier;
            } else {
                throw new IllegalArgumentException("Unable to determine key for row: " + row);
            }
        }
        return key;
    }


    /**
     * Get an alternate key from a row
     * <p>
     *
     * @return the alternative key
     */
    String getAlternateKey(final String currentKey) {
        String newKey = null;

        if (!existingKey(currentKey)) {
            newKey = currentKey;
        } else {
            int i = 1;
            newKey = currentKey + "-" + i;
            while (existingKey(newKey)) {
                i++;
                newKey = currentKey + "-" + i;
            }
        }
        return newKey;
    }


    /**
     * Create the headerLine for the result file
     *
     * @return the header line
     */
    private String createHeaderLine() {
        String compareHeader = Arrays.stream(Fields.values()).filter(item -> !item.equals(ROW_STATUS) && !item.equals(KEY_VALUE)).map(item -> item.toString()).collect(Collectors.joining("; "));
        return "Status; Key;" + // Status and key
                headerLineHelper(oldHeader, "Old") + "; " + // Header from old view
                headerLineHelper(newHeader, "New") + "; " + // Header from new view
                headerLineHelper(compareHeader, "Compare"); // Comparison
    }

    /**
     * Create a headerLine
     *
     * @param input  the input String
     * @param preFix the prefix for the headerLine
     * @return the headerLine
     */
    private String headerLineHelper(final String input, final String preFix) {
        return Arrays.stream(input.split(";"))
                .map(item -> preFix + " " + item)
                .collect(Collectors.joining("; "));
    }

}

