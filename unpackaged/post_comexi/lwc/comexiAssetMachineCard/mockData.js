/**
 * Datos simulados de la ficha de maquina.
 *
 * La maquina, sus componentes, los campos tecnicos y los casos salen de la org via
 * COMEXI_AssetOverviewController. Lo que hay aqui es lo que todavia no existe como
 * registro: el historial de intervenciones de once anos y el perfil de produccion.
 *
 * Se mantiene aparte y con este comentario a proposito, para que en la demo se pueda
 * decir con precision que parte de la pantalla es dato real de la plataforma y que
 * parte es relleno narrativo. Cuando Comexi cargue su historico de servicio, el
 * timeline pasa a salir de WorkOrder y este fichero desaparece.
 */

/** Intervenciones de la S2 DS de Roberts Mart, de la instalacion al caso actual. */
export const LIFECYCLE = [
    {
        id: 'lc-2015-install',
        year: '2015',
        date: 'Junio 2015',
        title: 'Instalacion y puesta en marcha',
        detail:
            'Entrega de la Proslit S2 DS con PC industrial Windows 7, CPU GL Simotion y CU Sinamics. Formacion de operadores en planta.',
        kind: 'install'
    },
    {
        id: 'lc-2017-warranty',
        year: '2017',
        date: 'Marzo 2017',
        title: 'Fin de garantia y paso a contrato Silver',
        detail:
            'Revision de fin de garantia sin incidencias. El cliente contrata mantenimiento preventivo anual.',
        kind: 'service'
    },
    {
        id: 'lc-2019-os',
        year: '2019',
        date: 'Septiembre 2019',
        title: 'Actualizacion del PC a Windows 10',
        detail:
            'Migracion del PC de linea de Windows 7 a Windows 10 sobre la misma electronica. Es la actualizacion que hoy vuelve a quedarse sin soporte.',
        kind: 'retrofit'
    },
    {
        id: 'lc-2021-screen',
        year: '2021',
        date: 'Noviembre 2021',
        title: 'Sustitucion de la pantalla de operador',
        detail:
            'Cambio de la pantalla de 15 pulgadas por rotura. Se aprovecho la parada para revisar el cableado del pupitre.',
        kind: 'service'
    },
    {
        id: 'lc-2024-preventive',
        year: '2024',
        date: 'Abril 2024',
        title: 'Mantenimiento preventivo mayor',
        detail:
            'Revision de husillos y grupos de corte a las 38.000 horas. Sin desviaciones sobre tolerancia de fabrica.',
        kind: 'service'
    },
    {
        id: 'lc-2026-case',
        year: '2026',
        date: 'Caso abierto',
        title: 'Windows 10 fuera de soporte',
        detail:
            'El cliente avisa de que seguridad corporativa va a auditar la red de planta. La maquina produce, pero el PC ya no recibe parches.',
        kind: 'alert'
    }
];

/** Perfil de produccion: da la medida de desgaste que la antiguedad sola no captura. */
export const OPERATING = {
    shifts: '3 turnos',
    hoursPerYear: 3900,
    availability: '94,2%',
    mainApplication: 'Corte de film flexible para envase alimentario'
};
