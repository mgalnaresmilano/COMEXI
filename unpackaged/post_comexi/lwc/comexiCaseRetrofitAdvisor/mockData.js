/**
 * Datos simulados del COMEXI Retrofit Advisor.
 *
 * El briefing del caso, la maquina y sus componentes salen de la org via Apex. Lo que
 * hay aqui es lo que todavia no existe como registro: el razonamiento del agente y los
 * precedentes de otros clientes. Los casos de RELATED_CASES son inventados a proposito,
 * sobre modelos que si estan en el catalogo Comexi Maquinaria, para que el barrido de
 * la base instalada global resulte creible sin ensuciar la org con datos falsos.
 */

export const RELATED_CASES = [
    {
        id: 'rc-171204',
        caseNumber: '171204',
        customer: 'Emballages Vidal SAS',
        country: 'Francia',
        machineModel: 'Comexi S1 DT',
        sku: 'MAQ-S1-DT',
        installYear: 2013,
        problem:
            'PC industrial con Windows 10 fuera de soporte. Seguridad corporativa desconecto la maquina de la red tras una auditoria.',
        resolution: 'Retrofit T100 con cambio de CPU Simotion. No necesito ingenieria de proyecto.',
        retrofit: 'T100 + T100-CPU-SIM',
        daysToClose: 34,
        amount: 7420,
        outcome: 'won'
    },
    {
        id: 'rc-169880',
        caseNumber: '169880',
        customer: 'Flexo Nord AB',
        country: 'Suecia',
        machineModel: 'Comexi S2 DT',
        sku: 'MAQ-S2-DT',
        installYear: 2016,
        problem:
            'Pantalla de operador de 15 pulgadas sin repuesto en el mercado. Cada parada obligaba a esperar a una unidad de segunda mano.',
        resolution: 'Retrofit T100 con cambio de pantalla y pupitre HMI en la misma intervencion.',
        retrofit: 'T100 + T100-SCREEN + T100-HMI',
        daysToClose: 41,
        amount: 9180,
        outcome: 'won'
    },
    {
        id: 'rc-168452',
        caseNumber: '168452',
        customer: 'Iberpack Converting SL',
        country: 'Espana',
        machineModel: 'Comexi S1 MS',
        sku: 'MAQ-S1-MS',
        installYear: 2011,
        problem:
            'CU Sinamics con fallos intermitentes de comunicacion. El cliente pedia presupuesto de retrofit completo.',
        resolution: 'Retrofit T100 con cambio de CU Sinamics. Se descarto la sustitucion de maquina.',
        retrofit: 'T100 + T100-CU-SIN',
        daysToClose: 28,
        amount: 6890,
        outcome: 'won'
    },
    {
        id: 'rc-166301',
        caseNumber: '166301',
        customer: 'Adriatica Films Srl',
        country: 'Italia',
        machineModel: 'Comexi S2 DS',
        sku: 'MAQ-S2-DS',
        installYear: 2014,
        problem:
            'Mismo escenario que el caso actual: PC con Windows 10 y CPU GL Simotion, mas peticion de control de temperatura de tinta.',
        resolution: 'Retrofit T100 con el add-on de temperatura de tinta como linea separada.',
        retrofit: 'T100 + T100-TEMP',
        daysToClose: 37,
        amount: 10240,
        outcome: 'won'
    },
    {
        id: 'rc-165117',
        caseNumber: '165117',
        customer: 'Baltic Flexibles UAB',
        country: 'Lituania',
        machineModel: 'Comexi S1 MT',
        sku: 'MAQ-S1-MT',
        installYear: 2004,
        problem:
            'PC con Windows XP y CPU no compatible con la base del retrofit. Requeria ingenieria de adaptacion.',
        resolution:
            'Se descarto el retrofit por coste de adaptacion. El cliente acabo comprando maquina nueva.',
        retrofit: 'No viable sin ingenieria',
        daysToClose: 62,
        amount: 0,
        outcome: 'lost'
    },
    {
        id: 'rc-174012',
        caseNumber: '174012',
        customer: 'Grupo Envaflex SA de CV',
        country: 'Mexico',
        machineModel: 'Comexi S2 DT',
        sku: 'MAQ-S2-DT',
        installYear: 2015,
        problem:
            'Peticion de actualizacion a Windows 11 antes del cierre de soporte, con checklist de numeros de serie para auditoria.',
        resolution: 'Oferta enviada con T100 y checklist. Pendiente de aprobacion del cliente.',
        retrofit: 'T100 + T100-CHECKLIST',
        daysToClose: null,
        amount: 7960,
        outcome: 'open'
    }
];

/** Etapas del razonamiento simulado, en el orden en que se van encendiendo. */
export const AGENT_STAGES = [
    {
        id: 'read',
        label: 'Leyendo el caso y la ficha de maquina',
        detail: 'Asunto, descripcion, contacto que reporta y configuracion instalada del asset.'
    },
    {
        id: 'installed',
        label: 'Barriendo la base instalada',
        detail: 'Componentes hijos del asset y su estado de soporte.'
    },
    {
        id: 'precedents',
        label: 'Cruzando con casos historicos',
        detail: 'Retrofits sobre maquinas de la misma linea en otros clientes.'
    },
    {
        id: 'catalog',
        label: 'Validando contra el catalogo de producto',
        detail: 'Solo se consideran SKUs activos del catalogo Comexi Servicio.'
    },
    {
        id: 'feasibility',
        label: 'Evaluando viabilidad tecnica',
        detail: 'Compatibilidad de CPU y CU con la base del retrofit T100.'
    }
];

/** Veredicto del agente. Las cifras son las del escandallo del caso 174535. */
export const RECOMMENDATION = {
    sku: 'T100',
    name: 'T100 - UPDATE PC',
    summary:
        'Migracion del PC industrial de Windows 10 a Windows 11 sobre la electronica ya instalada, sin sustituir la maquina.',
    feasibility: {
        verdict: 'Viable sin ingenieria',
        tone: 'good',
        reason:
            'La maquina monta CPU GL Simotion y CU Sinamics, que son compatibles con la base del retrofit T100. No hace falta pasar por ingenieria de proyecto, que es lo que hoy convierte cualquier retrofit en un proceso de tres personas.'
    },
    components: [
        { sku: 'T100-W11', name: 'Canvi de Windows 10 a Windows 11', role: 'Requerido', required: true },
        { sku: 'T100-CPU-SIM', name: 'Canvi CPU Simotion', role: 'Opcional', required: false },
        { sku: 'T100-CU-SIN', name: 'Canvi CU Sinamics', role: 'Opcional', required: false },
        { sku: 'T100-HMI', name: 'Pupitre HMI', role: 'Opcional', required: false },
        { sku: 'T100-SCREEN', name: 'Canvi de pantalla', role: 'Opcional', required: false },
        { sku: 'T100-CHECKLIST', name: 'Checklist amb numeros de serie', role: 'Opcional', required: false }
    ],
    addOn: {
        sku: 'T100-TEMP',
        name: 'Control de temperatura de tinta',
        price: '3.600,00 EUR',
        note: 'Linea independiente, no componente del bundle, para poder ensenar el precio basico y el add-on por separado.'
    },
    figures: [
        { label: 'Coste resultante', value: '4.923,49 EUR', tone: 'neutral' },
        { label: 'Precio de venta (margen 42%)', value: '7.321,39 EUR', tone: 'neutral' },
        { label: 'Precio final (-5%)', value: '6.955,32 EUR', tone: 'accent' },
        { label: 'Margen resultante', value: '27,54%', tone: 'warn' }
    ],
    guardrail: {
        title: 'El asesor no puede inventarse un codigo',
        body:
            'Cada SKU propuesto se valida contra el catalogo de producto antes de entrar en la recomendacion. Un codigo que no existe, como el P271 que aparecio en la sesion de discovery, se rechaza en vez de colarse en la oferta.'
    }
};
