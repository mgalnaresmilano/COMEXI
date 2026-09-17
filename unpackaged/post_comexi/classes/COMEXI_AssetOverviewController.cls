/**
 * Controlador de los dos LWC de la escena 01 del guion Comexi: comexiAssetMachineCard
 * y comexiAssetCaseAlert.
 *
 * La escena 01 tiene que demostrar que la maquina es un objeto de primera clase y no
 * una matricula en una celda del Launcher. Eso obliga a que todo lo que se ve en la
 * ficha salga de la org: los campos COMEXI_* del Asset, sus assets hijos (el PC, la
 * CPU, la CU y la pantalla) y los casos de servicio reales. Lo unico simulado vive en
 * el mockData.js del componente, y esta acotado al timeline de ciclo de vida, que
 * todavia no existe como registro.
 *
 * Reglas que condicionan el diseno:
 *
 *  - Una query por objeto. La maquina y sus componentes salen de la misma consulta
 *    (Id = :assetId OR ParentId = :assetId), como ya hace loadMachine en
 *    COMEXI_RetrofitAdvisorController.
 *  - La foto no se guarda en el Asset: se resuelve desde el SKU del producto contra el
 *    static resource COMEXI_MachineryImages, asi que funciona para cualquier maquina
 *    del parque y no solo para la S2 DS del caso 174535.
 *  - getOpenCaseAlert devuelve null cuando no hay caso abierto. El LWC no renderiza
 *    nada en ese caso, para no dejar una banda roja vacia en el resto de la base
 *    instalada.
 */
public with sharing class COMEXI_AssetOverviewController {

    /** Static resource con una foto por SKU de maquina (MAQ-S2-DS.jpg y companeros). */
    private static final String MACHINERY_RESOURCE = '/resource/COMEXI_MachineryImages/';

    /**
     * El caso con el que arranca la demo lleva el numero de expediente de Comexi en el
     * asunto, no en CaseNumber: el CaseNumber lo asigna la org. Se prioriza para que la
     * banda apunte siempre al caso del guion aunque haya otros casos abiertos.
     */
    private static final String DEMO_CASE_MARKER = '174535';

    /** Sistemas operativos sin soporte del fabricante: son los que justifican el retrofit. */
    private static final Set<String> OUT_OF_SUPPORT_OS =
        new Set<String>{ 'Windows XP', 'Windows 7', 'Windows 10' };

    // ─────────────────────────────────────────────────────────────────────────────
    // Ficha de la maquina
    // ─────────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static AssetOverview getAssetOverview(Id assetId) {
        try {
            if (assetId == null) return null;

            // La maquina y sus componentes en una sola consulta.
            List<Asset> assets = [
                SELECT Id, Name, SerialNumber, Status, InstallDate, ParentId,
                       CurrencyIsoCode,
                       AccountId, Account.Name,
                       Product2Id, Product2.Name, Product2.StockKeepingUnit,
                       Product2.DisplayUrl,
                       COMEXI_Machine_Model__c, COMEXI_Install_Year__c,
                       COMEXI_Machine_Age_Years__c, COMEXI_Line__c,
                       COMEXI_Installed_Config__c, COMEXI_Control_System__c,
                       COMEXI_SAP_Equipment_Code__c, COMEXI_Web_Width_mm__c,
                       COMEXI_Stations__c, COMEXI_Max_Speed_Mpm__c,
                       COMEXI_OS_Installed__c, COMEXI_OS_Support_End__c,
                       COMEXI_Obsolete_Component__c, COMEXI_Obsolescence_Risk__c,
                       COMEXI_Retrofit_Eligible__c, COMEXI_Requires_Engineering__c,
                       COMEXI_Recommended_Retrofit_SKU__c,
                       COMEXI_Service_Level__c, COMEXI_Last_Intervention_Date__c,
                       COMEXI_Intervention_Count__c, COMEXI_Operating_Hours__c,
                       COMEXI_Service_Revenue_Lifetime__c, COMEXI_Open_Cases__c,
                       COMEXI_Site_Location__c, COMEXI_Retrofits_Applied__c,
                       COMEXI_Last_Retrofit_Date__c, COMEXI_Retrofit_Potential_Value__c
                FROM Asset
                WHERE Id = :assetId OR ParentId = :assetId
                WITH USER_MODE
                ORDER BY Name
            ];
            if (assets.isEmpty()) return null;

            AssetOverview overview = new AssetOverview();
            overview.components = new List<MachineComponent>();

            for (Asset a : assets) {
                if (a.Id == assetId) {
                    overview.machine = toMachine(a);
                } else {
                    overview.components.add(toComponent(a));
                }
            }
            if (overview.machine == null) return null;

            overview.cases = loadCases(assetId);
            overview.openCaseCount = 0;
            for (CaseRow row : overview.cases) {
                if (!row.isClosed) overview.openCaseCount++;
            }
            return overview;

        } catch (Exception e) {
            throw asAura(e);
        }
    }

    private static Machine toMachine(Asset a) {
        Machine m = new Machine();
        m.id           = a.Id;
        m.name         = a.Name;
        m.serialNumber = a.SerialNumber;
        m.status       = a.Status;
        m.installDate  = a.InstallDate;
        m.currencyCode = a.CurrencyIsoCode;
        m.accountId    = a.AccountId;
        m.accountName  = (a.Account != null) ? a.Account.Name : null;
        m.productName  = (a.Product2 != null) ? a.Product2.Name : null;
        m.sku          = (a.Product2 != null) ? a.Product2.StockKeepingUnit : null;
        m.imageUrl     = resolveImageUrl(a);

        m.model           = a.COMEXI_Machine_Model__c;
        m.line            = a.COMEXI_Line__c;
        m.installedConfig = a.COMEXI_Installed_Config__c;
        m.controlSystem   = a.COMEXI_Control_System__c;
        m.sapEquipmentCode = a.COMEXI_SAP_Equipment_Code__c;
        m.installYear     = toInteger(a.COMEXI_Install_Year__c);
        m.webWidthMm      = toInteger(a.COMEXI_Web_Width_mm__c);
        m.stations        = toInteger(a.COMEXI_Stations__c);
        m.maxSpeedMpm     = toInteger(a.COMEXI_Max_Speed_Mpm__c);

        // La formula ya calcula la antiguedad; el fallback cubre el asset sin sellar.
        m.ageYears = (a.COMEXI_Machine_Age_Years__c != null)
            ? toInteger(a.COMEXI_Machine_Age_Years__c)
            : (m.installYear != null ? Date.today().year() - m.installYear : null);

        m.osInstalled        = a.COMEXI_OS_Installed__c;
        m.osSupportEnd       = a.COMEXI_OS_Support_End__c;
        m.osOutOfSupport     = OUT_OF_SUPPORT_OS.contains(a.COMEXI_OS_Installed__c);
        m.obsoleteComponent  = a.COMEXI_Obsolete_Component__c;
        m.obsolescenceRisk   = a.COMEXI_Obsolescence_Risk__c;
        m.retrofitEligible   = a.COMEXI_Retrofit_Eligible__c;
        m.requiresEngineering = a.COMEXI_Requires_Engineering__c;
        m.recommendedSku     = a.COMEXI_Recommended_Retrofit_SKU__c;

        m.serviceLevel           = a.COMEXI_Service_Level__c;
        m.lastInterventionDate   = a.COMEXI_Last_Intervention_Date__c;
        m.interventionCount      = toInteger(a.COMEXI_Intervention_Count__c);
        m.operatingHours         = toInteger(a.COMEXI_Operating_Hours__c);
        m.serviceRevenueLifetime = a.COMEXI_Service_Revenue_Lifetime__c;

        m.siteLocation          = a.COMEXI_Site_Location__c;
        m.retrofitsApplied      = a.COMEXI_Retrofits_Applied__c;
        m.lastRetrofitDate      = a.COMEXI_Last_Retrofit_Date__c;
        m.retrofitPotentialValue = a.COMEXI_Retrofit_Potential_Value__c;
        return m;
    }

    private static MachineComponent toComponent(Asset a) {
        MachineComponent mc = new MachineComponent();
        mc.id           = a.Id;
        mc.name         = a.Name;
        mc.serialNumber = a.SerialNumber;
        mc.config       = a.COMEXI_Installed_Config__c;
        mc.productName  = (a.Product2 != null) ? a.Product2.Name : null;
        mc.sku          = (a.Product2 != null) ? a.Product2.StockKeepingUnit : null;
        mc.installDate  = a.InstallDate;
        // El componente en riesgo es el que corre el sistema operativo fuera de soporte:
        // mismo criterio que loadMachine en COMEXI_RetrofitAdvisorController.
        mc.atRisk = (mc.config != null && mc.config.containsIgnoreCase('Windows'));
        return mc;
    }

    /**
     * Product2.DisplayUrl ya apunta al static resource en el catalogo de maquinaria, pero
     * los productos de componente instalado no tienen imagen. Se reconstruye desde el SKU
     * para que la ficha nunca salga sin foto.
     */
    private static String resolveImageUrl(Asset a) {
        if (a.Product2 == null) return null;
        if (String.isNotBlank(a.Product2.DisplayUrl)) return a.Product2.DisplayUrl;
        if (String.isBlank(a.Product2.StockKeepingUnit)) return null;
        return MACHINERY_RESOURCE + a.Product2.StockKeepingUnit + '.jpg';
    }

    private static List<CaseRow> loadCases(Id assetId) {
        List<CaseRow> rows = new List<CaseRow>();
        for (Case c : [
            SELECT Id, CaseNumber, Subject, Description, Status, Priority, IsClosed,
                   CreatedDate, Contact.Name
            FROM Case
            WHERE AssetId = :assetId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 10
        ]) {
            rows.add(toCaseRow(c));
        }
        return rows;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Alerta de caso abierto
    // ─────────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static CaseRow getOpenCaseAlert(Id assetId) {
        try {
            if (assetId == null) return null;

            List<Case> openCases = [
                SELECT Id, CaseNumber, Subject, Description, Status, Priority,
                       IsClosed, CreatedDate, Contact.Name
                FROM Case
                WHERE AssetId = :assetId AND IsClosed = false
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
            if (openCases.isEmpty()) return null;

            // El caso del guion manda sobre la fecha: si esta abierto, es el que la banda
            // tiene que ofrecer, porque es donde arranca la demo.
            for (Case c : openCases) {
                if (c.Subject != null && c.Subject.contains(DEMO_CASE_MARKER)) {
                    return toCaseRow(c);
                }
            }
            return toCaseRow(openCases[0]);

        } catch (Exception e) {
            throw asAura(e);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Resolucion de destinos de navegacion para el panel de la home
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * El comexiRevenueDashboard trabaja con datos mock: el parque de 428 maquinas y la
     * cartera de ofertas no existen como registros. Pero el embudo tiene que poder
     * saltar a la maquina real con la que arranca la demo, asi que aqui se traducen los
     * numeros de serie del mock a los Id de la org.
     *
     * Los numeros de serie que no existen no vuelven en la lista: es el LWC el que
     * decide pintar esa fila sin enlace, en vez de ofrecer un enlace que no lleva a
     * ningun sitio.
     */
    @AuraEnabled(cacheable=true)
    public static List<RetrofitTarget> getRetrofitNavTargets(List<String> serialNumbers) {
        try {
            if (serialNumbers == null || serialNumbers.isEmpty()) {
                return new List<RetrofitTarget>();
            }

            Map<Id, RetrofitTarget> byAssetId = new Map<Id, RetrofitTarget>();
            for (Asset a : [
                SELECT Id, Name, SerialNumber, COMEXI_Machine_Model__c
                FROM Asset
                WHERE SerialNumber IN :serialNumbers
                WITH USER_MODE
            ]) {
                RetrofitTarget t = new RetrofitTarget();
                t.serial    = a.SerialNumber;
                t.assetId   = a.Id;
                t.assetName = a.Name;
                t.model     = a.COMEXI_Machine_Model__c;
                byAssetId.put(a.Id, t);
            }
            if (byAssetId.isEmpty()) return new List<RetrofitTarget>();

            // Una sola consulta para todos los assets. El ORDER BY ascendente deja el
            // caso mas reciente como ultimo en sobrescribir, que es el que interesa.
            for (Case c : [
                SELECT Id, CaseNumber, Subject, AssetId
                FROM Case
                WHERE AssetId IN :byAssetId.keySet() AND IsClosed = false
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ]) {
                RetrofitTarget t = byAssetId.get(c.AssetId);
                if (t == null) continue;
                t.caseId        = c.Id;
                t.caseNumber    = c.CaseNumber;
                t.caseSubject   = c.Subject;
                t.caseReference = extractReference(c.Subject);
            }
            return byAssetId.values();

        } catch (Exception e) {
            throw asAura(e);
        }
    }

    private static CaseRow toCaseRow(Case c) {
        CaseRow row = new CaseRow();
        row.id          = c.Id;
        row.caseNumber  = c.CaseNumber;
        row.subject     = c.Subject;
        row.description = c.Description;
        row.status      = c.Status;
        row.priority    = c.Priority;
        row.isClosed    = c.IsClosed;
        row.createdDate = c.CreatedDate;
        row.contactName = (c.Contact != null) ? c.Contact.Name : null;
        // El numero de expediente de Comexi va delante del asunto ("174535 - PC + Win"),
        // y es el que el cliente reconoce, no el CaseNumber que asigna Salesforce.
        row.reference = extractReference(c.Subject);
        row.isRetrofit = isRetrofitCase(c);
        return row;
    }

    /**
     * La banda solo se etiqueta como retrofit cuando el caso lo es. El resto del parque
     * tiene casos abiertos que no van de obsolescencia (peticiones de recambio, por
     * ejemplo) y etiquetarlos de retrofit seria mentir en la cabecera del Asset.
     */
    private static Boolean isRetrofitCase(Case c) {
        String haystack = (c.Subject == null ? '' : c.Subject)
            + ' ' + (c.Description == null ? '' : c.Description);
        return haystack.contains(DEMO_CASE_MARKER)
            || haystack.containsIgnoreCase('retrofit')
            || haystack.containsIgnoreCase('obsolet');
    }

    private static String extractReference(String subject) {
        if (String.isBlank(subject)) return null;
        Matcher m = Pattern.compile('^\\s*(\\d{4,})').matcher(subject);
        return m.find() ? m.group(1) : null;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Utilidades
    // ─────────────────────────────────────────────────────────────────────────────

    private static Integer toInteger(Decimal value) {
        return (value == null) ? null : Integer.valueOf(value);
    }

    private static AuraHandledException asAura(Exception e) {
        if (e instanceof AuraHandledException) return (AuraHandledException) e;
        AuraHandledException aura = new AuraHandledException(e.getMessage());
        aura.setMessage(e.getMessage());
        return aura;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Wrappers
    // ─────────────────────────────────────────────────────────────────────────────

    public class AssetOverview {
        @AuraEnabled public Machine machine;
        @AuraEnabled public List<MachineComponent> components;
        @AuraEnabled public List<CaseRow> cases;
        @AuraEnabled public Integer openCaseCount;
    }

    public class Machine {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Date installDate;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String productName;
        @AuraEnabled public String sku;
        @AuraEnabled public String imageUrl;

        @AuraEnabled public String model;
        @AuraEnabled public String line;
        @AuraEnabled public String installedConfig;
        @AuraEnabled public String controlSystem;
        @AuraEnabled public String sapEquipmentCode;
        @AuraEnabled public Integer installYear;
        @AuraEnabled public Integer ageYears;
        @AuraEnabled public Integer webWidthMm;
        @AuraEnabled public Integer stations;
        @AuraEnabled public Integer maxSpeedMpm;

        @AuraEnabled public String osInstalled;
        @AuraEnabled public Date osSupportEnd;
        @AuraEnabled public Boolean osOutOfSupport;
        @AuraEnabled public String obsoleteComponent;
        @AuraEnabled public String obsolescenceRisk;
        @AuraEnabled public Boolean retrofitEligible;
        @AuraEnabled public Boolean requiresEngineering;
        @AuraEnabled public String recommendedSku;

        @AuraEnabled public String serviceLevel;
        @AuraEnabled public Date lastInterventionDate;
        @AuraEnabled public Integer interventionCount;
        @AuraEnabled public Integer operatingHours;
        @AuraEnabled public Decimal serviceRevenueLifetime;

        @AuraEnabled public String siteLocation;
        @AuraEnabled public String retrofitsApplied;
        @AuraEnabled public Date lastRetrofitDate;
        @AuraEnabled public Decimal retrofitPotentialValue;
    }

    public class MachineComponent {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String sku;
        @AuraEnabled public String config;
        @AuraEnabled public Date installDate;
        @AuraEnabled public Boolean atRisk;
    }

    /** Traduccion de un numero de serie del mock a los Id reales de la org. */
    public class RetrofitTarget {
        @AuraEnabled public String serial;
        @AuraEnabled public String assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String model;
        @AuraEnabled public String caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String caseSubject;
        @AuraEnabled public String caseReference;
    }

    public class CaseRow {
        @AuraEnabled public String id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String reference;
        @AuraEnabled public String subject;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Boolean isClosed;
        @AuraEnabled public Boolean isRetrofit;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String contactName;
    }
}
