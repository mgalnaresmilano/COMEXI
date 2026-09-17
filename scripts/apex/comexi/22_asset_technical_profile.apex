// Escena 01: sella el perfil tecnico, de obsolescencia y de servicio de la base instalada.
//
// Los 23 campos COMEXI nuevos del Asset no valen nada vacios: la escena 01 se apoya en
// que la maquina tenga ficha, historico y veredicto. Esto los rellena de forma coherente
// con el guion y, sobre todo, coherente entre las dos maquinas del parque:
//
//   MSC000600 (2015, Windows 10) -> elegible, sin ingenieria, retrofit T100.
//   MSC000123 (2001, Windows XP) -> elegible pero requiere ingenieria de proyecto.
//
// Ese contraste es lo que hace creible el veredicto del Advisor en la escena 02: no puede
// decir "viable" sobre las dos, y el dato tiene que respaldar por que.
//
// Los casos abiertos se cuentan con una sola agregada y se sellan en bloque: sin ellos
// Asset.COMEXI_Open_Cases__c queda a cero y el dato no cuadra con la banda de alerta.
//
// Idempotente: relanzarlo deja los mismos valores.

final Date TODAY = Date.today();

// ---------- Perfil por numero de serie ----------
// El PC de MSC000600 migro de Windows 7 a Windows 10 en 2019, y esa migracion es
// justamente la que hoy vuelve a quedarse sin soporte. Windows 10 termino soporte el
// 14/10/2025, asi que la maquina ya esta fuera y el caso no es preventivo: es tardio.
Map<String, Asset> profile = new Map<String, Asset>{
    'MSC000600' => new Asset(
        // Ficha tecnica
        COMEXI_Web_Width_mm__c        = 1270,
        COMEXI_Stations__c            = 2,
        COMEXI_Max_Speed_Mpm__c       = 500,
        COMEXI_Control_System__c      = 'Simotion GL + Sinamics',
        COMEXI_SAP_Equipment_Code__c  = 'SAP-EQ-MSC000600',
        // Obsolescencia y viabilidad
        COMEXI_OS_Installed__c              = 'Windows 10',
        COMEXI_OS_Support_End__c            = Date.newInstance(2025, 10, 14),
        COMEXI_Obsolete_Component__c        = 'PC industrial de linea con Windows 10',
        COMEXI_Obsolescence_Risk__c         = 'Critico',
        COMEXI_Retrofit_Eligible__c         = true,
        COMEXI_Requires_Engineering__c      = false,
        COMEXI_Recommended_Retrofit_SKU__c  = 'T100',
        // Servicio e historico
        COMEXI_Service_Level__c             = 'Silver',
        COMEXI_Last_Intervention_Date__c    = Date.newInstance(2024, 4, 18),
        COMEXI_Intervention_Count__c        = 14,
        COMEXI_Operating_Hours__c           = 42300,
        COMEXI_Service_Revenue_Lifetime__c  = 38450.00,
        // Retrofit y emplazamiento
        COMEXI_Site_Location__c             = 'Leeds, United Kingdom',
        COMEXI_Retrofits_Applied__c         = 'T100-W10 (2019), T100-SCREEN (2021)',
        COMEXI_Last_Retrofit_Date__c        = Date.newInstance(2021, 11, 9),
        COMEXI_Retrofit_Potential_Value__c  = 15322.18
    ),
    'MSC000123' => new Asset(
        COMEXI_Web_Width_mm__c        = 1050,
        COMEXI_Stations__c            = 2,
        COMEXI_Max_Speed_Mpm__c       = 350,
        COMEXI_Control_System__c      = 'Control analogico de generacion previa a Simotion',
        COMEXI_SAP_Equipment_Code__c  = 'SAP-EQ-MSC000123',
        COMEXI_OS_Installed__c              = 'Windows XP',
        COMEXI_OS_Support_End__c            = Date.newInstance(2014, 4, 8),
        COMEXI_Obsolete_Component__c        = 'PC industrial con Windows XP y CPU sin equivalencia actual',
        COMEXI_Obsolescence_Risk__c         = 'Critico',
        COMEXI_Retrofit_Eligible__c         = true,
        // El retrofit es posible, pero sin CPU GL compatible hay que redisenar el
        // armario de control: por eso esta maquina si pasa por ingenieria.
        COMEXI_Requires_Engineering__c      = true,
        COMEXI_Recommended_Retrofit_SKU__c  = 'T100',
        COMEXI_Service_Level__c             = 'Sin contrato',
        COMEXI_Last_Intervention_Date__c    = Date.newInstance(2019, 9, 26),
        COMEXI_Intervention_Count__c        = 27,
        COMEXI_Operating_Hours__c           = 71800,
        COMEXI_Service_Revenue_Lifetime__c  = 61200.00,
        COMEXI_Site_Location__c             = 'Leeds, United Kingdom',
        COMEXI_Retrofits_Applied__c         = 'T100-W10 (2011)',
        COMEXI_Last_Retrofit_Date__c        = Date.newInstance(2011, 5, 17),
        COMEXI_Retrofit_Potential_Value__c  = 24800.00
    )
};

// ---------- Casos abiertos por maquina ----------
// Una sola agregada, no una query por asset.
Map<Id, Integer> openCasesByAsset = new Map<Id, Integer>();
for (AggregateResult ar : [
    SELECT AssetId aid, COUNT(Id) total
    FROM Case
    WHERE AssetId != null AND IsClosed = false
    GROUP BY AssetId
]) {
    openCasesByAsset.put((Id) ar.get('aid'), (Integer) ar.get('total'));
}

// ---------- Sellado ----------
List<Asset> toUpdate = new List<Asset>();

for (Asset a : [
    SELECT Id, Name, SerialNumber, ParentId, COMEXI_Install_Year__c,
           COMEXI_Machine_Model__c, COMEXI_Site_Location__c
    FROM Asset
]) {
    Asset src = profile.get(a.SerialNumber);

    if (src != null) {
        // Maquina raiz: perfil completo.
        Asset upd = src.clone(false, true, false, false);
        upd.Id = a.Id;
        upd.COMEXI_Open_Cases__c = openCasesByAsset.containsKey(a.Id)
            ? openCasesByAsset.get(a.Id) : 0;
        toUpdate.add(upd);
        continue;
    }

    if (a.ParentId == null) continue;

    // Componente: solo lo que tiene sentido a nivel de pieza. El emplazamiento se
    // hereda de la maquina para que los gastos de desplazamiento cuadren en la oferta
    // independientemente de a que asset se enganche la linea.
    toUpdate.add(new Asset(
        Id = a.Id,
        COMEXI_Site_Location__c = 'Leeds, United Kingdom',
        COMEXI_Open_Cases__c = openCasesByAsset.containsKey(a.Id)
            ? openCasesByAsset.get(a.Id) : 0
    ));
}

if (!toUpdate.isEmpty()) update toUpdate;
System.debug('Assets sellados: ' + toUpdate.size());

// ---------- Verificacion ----------
for (Asset a : [
    SELECT Name, COMEXI_Machine_Model__c, COMEXI_Machine_Age_Years__c,
           COMEXI_OS_Installed__c, COMEXI_Obsolescence_Risk__c,
           COMEXI_Retrofit_Eligible__c, COMEXI_Requires_Engineering__c,
           COMEXI_Operating_Hours__c, COMEXI_Open_Cases__c
    FROM Asset
    WHERE SerialNumber IN :profile.keySet()
    ORDER BY Name
]) {
    System.debug(a.Name + ' | ' + a.COMEXI_Machine_Model__c
        + ' | ' + a.COMEXI_Machine_Age_Years__c + ' anos'
        + ' | ' + a.COMEXI_OS_Installed__c
        + ' | riesgo ' + a.COMEXI_Obsolescence_Risk__c
        + ' | elegible ' + a.COMEXI_Retrofit_Eligible__c
        + ' | ingenieria ' + a.COMEXI_Requires_Engineering__c
        + ' | ' + a.COMEXI_Operating_Hours__c + ' h'
        + ' | ' + a.COMEXI_Open_Cases__c + ' casos abiertos');
}
