/**
 * Dataset mock del dashboard de Revenue Cloud de Comexi.
 *
 * Todo el dato vive aqui para poder recalibrarlo antes de la demo sin tocar la UI.
 * Las cifras se anclan al caso real 174535 observado en la sesion de discovery
 * (coste 4.923,49 EUR, precio de venta con margen 42% 7.321,39 EUR, precio final
 * tras -5% 6.955,32 EUR, margen resultante 27,54%). El resto de registros se generan
 * de forma determinista para que los KPIs sean coherentes y repetibles en cada pase.
 */

const CURRENT_COMMERCIAL = 'Marc Vidal';
const MARGIN_FLOOR = 30; // umbral minimo de margen que dispara aprobacion
const ANNUAL_TARGET = 2_600_000; // objetivo anual de bookings de servicio (EUR)

const REPS = ['Marc Vidal', 'Nuria Serra', 'Jordi Puig', 'Elena Ferrer', 'David Prieto'];

const FAMILIES = [
    { code: 'FAM_T', label: 'Tall / Slitting', target: 40 },
    { code: 'FAM_L', label: 'Laminacio i Calandres', target: 25 },
    { code: 'FAM_C', label: 'Periferics CTEC', target: 25 },
    { code: 'FAM_P', label: 'Peces', target: 40 },
    { code: 'SERVICE', label: 'Servei (packs)', target: 40 },
    { code: 'GASTOS', label: 'Despeses i intervencio', target: 10 }
];

const LINES = [
    { code: 'T', label: 'Linia T - Tall' },
    { code: 'L', label: 'Linia L - Laminacio' },
    { code: 'C', label: 'Linia C - CTEC' }
];

const COUNTRIES = [
    { code: 'UK', label: 'Regne Unit', hasRep: true },
    { code: 'DE', label: 'Alemanya', hasRep: true },
    { code: 'FR', label: 'Franca', hasRep: true },
    { code: 'IT', label: 'Italia', hasRep: false },
    { code: 'ES', label: 'Espanya', hasRep: false },
    { code: 'BR', label: 'Brasil', hasRep: true },
    { code: 'MX', label: 'Mexic', hasRep: true },
    { code: 'TR', label: 'Turquia', hasRep: false },
    { code: 'IN', label: 'India', hasRep: false },
    { code: 'AU', label: 'Australia', hasRep: true }
];

const MONTHS = ['Gen', 'Feb', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago'];

const ACCOUNTS = [
    'Roberts Mart Co Ltd', 'Flexo Iberica SA', 'PrintPack Deutschland GmbH',
    'Embalatges Girona SL', 'Nordic Converting AS', 'Pack Solutions France',
    'Adriatica Film Srl', 'Anadolu Ambalaj AS', 'Sao Paulo Filmes Ltda',
    'Grupo Envex Mexico', 'Mumbai FlexiPrint Pvt', 'Sydney Web Packaging'
];

const MACHINE_MODELS = [
    'Proslit S2 DS', 'Proslit S1', 'Nexus L2', 'Nexus L20', 'CI8 Flexo',
    'Nova SL2', 'F2 MB', 'Slitter S3'
];

/* ---------- Generador pseudoaleatorio determinista ---------- */

function makeRng(seed) {
    let s = seed >>> 0;
    return function next() {
        s = (s * 1664525 + 1013904223) >>> 0;
        return s / 4294967296;
    };
}

function pick(rng, arr) {
    return arr[Math.floor(rng() * arr.length)];
}

function round2(n) {
    return Math.round(n * 100) / 100;
}

/* ---------- Oferta ancla del caso 174535 ---------- */

const ANCHOR_OFFER = {
    id: 'Q-174535',
    name: 'Oferta 174535 - T100 UPDATE PC',
    account: 'Roberts Mart Co Ltd',
    asset: 'MSC000600',
    machineModel: 'Proslit S2 DS',
    line: 'T',
    family: 'FAM_T',
    country: 'UK',
    rep: CURRENT_COMMERCIAL,
    amount: 6955.32,
    cost: 4923.49,
    marginPct: 27.54,
    discountPct: 5,
    status: 'Pendent aprovacio',
    stage: 'Presentada',
    addOn: true,
    versions: 2,
    ageDays: 3,
    quoteDays: 2,
    monthIdx: 7,
    converted: false,
    isAnchor: true
};

const STATUSES = ['Esborrany', 'Presentada', 'Pendent aprovacio', 'Acceptada', 'Rebutjada'];
const STAGE_BY_STATUS = {
    Esborrany: 'Borrador',
    Presentada: 'Presentada',
    'Pendent aprovacio': 'Presentada',
    Acceptada: 'Acceptada',
    Rebutjada: 'Presentada'
};

/* ---------- Generacion del universo de ofertas ---------- */

function buildOffers() {
    const rng = makeRng(174535);
    const offers = [ANCHOR_OFFER];

    for (let i = 0; i < 78; i++) {
        const line = pick(rng, LINES).code;
        const family = line === 'T' ? 'FAM_T' : line === 'L' ? 'FAM_L' : 'FAM_C';
        const country = pick(rng, COUNTRIES).code;
        const rep = pick(rng, REPS);
        const monthIdx = Math.floor(rng() * MONTHS.length);
        const base = 3500 + rng() * 22000;
        const targetMargin = pick(rng, [40, 25, 40, 40, 25]);
        const discountPct = round2(rng() * 12);
        // el descuento erosiona el margen partiendo del objetivo
        const marginPct = round2(Math.max(6, targetMargin - discountPct * (1.1 + rng() * 0.9)));
        const amount = round2(base);
        const cost = round2(amount * (1 - marginPct / 100));
        const r = rng();
        let status;
        if (r < 0.28) status = 'Acceptada';
        else if (r < 0.42) status = 'Rebutjada';
        else if (r < 0.58) status = marginPct < MARGIN_FLOOR ? 'Pendent aprovacio' : 'Presentada';
        else if (r < 0.78) status = 'Presentada';
        else status = 'Esborrany';

        offers.push({
            id: `Q-${10200 + i}`,
            name: `Oferta ${10200 + i}`,
            account: pick(rng, ACCOUNTS),
            asset: `MSC${String(100 + Math.floor(rng() * 800)).padStart(6, '0')}`,
            machineModel: pick(rng, MACHINE_MODELS),
            line,
            family,
            country,
            rep,
            amount,
            cost,
            marginPct,
            discountPct,
            status,
            stage: STAGE_BY_STATUS[status],
            addOn: rng() < 0.34,
            versions: 1 + Math.floor(rng() * 3),
            ageDays: 1 + Math.floor(rng() * 45),
            quoteDays: 1 + Math.floor(rng() * 9),
            monthIdx,
            converted: status === 'Acceptada' && rng() < 0.82,
            isAnchor: false
        });
    }
    return offers;
}

const ALL_OFFERS = buildOffers();

/* ---------- Casos de servicio sin oferta ---------- */

/** Expediente con el que arranca la demo: manda sobre la antiguedad en los listados. */
const ANCHOR_CASE_ID = '174535';

const CASES_WITHOUT_OFFER = [
    {
        id: '174535',
        subject: 'PC + Win - actualitzem oferta W11',
        account: 'Roberts Mart Co Ltd',
        asset: 'MSC000600',
        line: 'T',
        country: 'UK',
        ageDays: 1,
        priority: 'Alta'
    },
    {
        id: '174602',
        subject: 'Canvi CU Sinamics fora de servei',
        account: 'Flexo Iberica SA',
        asset: 'MSC000451',
        line: 'T',
        country: 'ES',
        ageDays: 4,
        priority: 'Mitjana'
    },
    {
        id: '174711',
        subject: 'Guiador de banda per talladora',
        account: 'Adriatica Film Srl',
        asset: 'MSC000288',
        line: 'T',
        country: 'IT',
        ageDays: 6,
        priority: 'Mitjana'
    },
    {
        id: '174788',
        subject: 'Migracio Parker a Sinamics',
        account: 'PrintPack Deutschland GmbH',
        asset: 'MSC000512',
        line: 'L',
        country: 'DE',
        ageDays: 9,
        priority: 'Baixa'
    },
    {
        id: '174820',
        subject: 'Productivitat flexografia CTEC',
        account: 'Sao Paulo Filmes Ltda',
        asset: 'MSC000733',
        line: 'C',
        country: 'BR',
        ageDays: 11,
        priority: 'Baixa'
    }
];

/* ---------- Base instalada / campana de obsolescencia ---------- */

const INSTALLED_BASE = {
    totalMachines: 428,
    countries: 34,
    obsoleteMachines: 62,
    obsoletePotential: 1_240_000,
    campaign: [
        { asset: 'MSC000600', account: 'Roberts Mart Co Ltd', model: 'Proslit S2 DS', component: 'PC Windows XP/10', installYear: 2015, potential: 6955, line: 'T' },
        { asset: 'MSC000123', account: 'Nordic Converting AS', model: 'Proslit S1', component: 'CPU GL fi de vida', installYear: 2001, potential: 18400, line: 'T' },
        { asset: 'MSC000451', account: 'Flexo Iberica SA', model: 'Nexus L2', component: 'CU Sinamics', installYear: 2004, potential: 12300, line: 'L' },
        { asset: 'MSC000512', account: 'PrintPack Deutschland GmbH', model: 'Nexus L20', component: 'Driver Parker', installYear: 1999, potential: 21750, line: 'L' },
        { asset: 'MSC000733', account: 'Sao Paulo Filmes Ltda', model: 'CI8 Flexo', component: 'Pantalla HMI', installYear: 2007, potential: 9800, line: 'C' },
        { asset: 'MSC000288', account: 'Adriatica Film Srl', model: 'Slitter S3', component: 'PC Windows XP', installYear: 2003, potential: 7100, line: 'T' }
    ]
};

/* ---------- Down payment pendiente ---------- */

const DOWN_PAYMENTS = {
    pendingOrders: 7,
    pendingAmount: 184_500,
    avgDaysBlocked: 12
};

/* ---------- Backlog de intervencion ---------- */

const INTERVENTION_BACKLOG = {
    committedHours: 1_940,
    weeksLoad: 6.2,
    technicians: 8
};

/* ---------- Waterfall del escandallo (caso 174535) ---------- */

const ANCHOR_WATERFALL = [
    { label: 'Cost material + hores', value: 4923.49, kind: 'base' },
    { label: 'Uplift garantia 2,60%', value: 128.01, kind: 'add' },
    { label: 'Uplift RALF 3,00%', value: 151.55, kind: 'add' },
    { label: 'Risc pais (UK)', value: 96.4, kind: 'add' },
    { label: 'Comissio representant 8%', value: 556.11, kind: 'add' },
    { label: 'Marge producte 40%', value: 1465.83, kind: 'margin' },
    { label: 'Preu de venda', value: 7321.39, kind: 'subtotal' },
    { label: 'Descompte -5%', value: -366.07, kind: 'discount' },
    { label: 'Preu final', value: 6955.32, kind: 'total' }
];

/* ---------- Formateo ---------- */

const EUR = new Intl.NumberFormat('es-ES', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 });
const EUR2 = new Intl.NumberFormat('es-ES', { style: 'currency', currency: 'EUR', minimumFractionDigits: 2, maximumFractionDigits: 2 });
const NUM = new Intl.NumberFormat('es-ES');

function fmtEur(n) {
    return EUR.format(Math.round(n));
}
function fmtEur2(n) {
    return EUR2.format(n);
}
function fmtEurK(n) {
    if (Math.abs(n) >= 1000) return `${round2(n / 1000)} k EUR`.replace('.', ',');
    return fmtEur(n);
}
function fmtPct(n) {
    return `${NUM.format(round2(n))} %`;
}
function fmtNum(n) {
    return NUM.format(n);
}

/* ---------- Utilidades de filtrado ---------- */

function periodMonthRange(period) {
    switch (period) {
        case 'month':
            return [7, 7];
        case 'quarter':
            return [5, 7];
        case '12m':
            return [0, 7];
        case 'ytd':
        default:
            return [0, 7];
    }
}

function filterOffers(role, filters) {
    const [minM, maxM] = periodMonthRange(filters.period);
    return ALL_OFFERS.filter((o) => {
        if (o.monthIdx < minM || o.monthIdx > maxM) return false;
        if (filters.line !== 'all' && o.line !== filters.line) return false;
        if (filters.country !== 'all' && o.country !== filters.country) return false;
        if (role === 'commercial') {
            if (o.rep !== CURRENT_COMMERCIAL) return false;
        } else if (filters.rep !== 'all' && o.rep !== filters.rep) {
            return false;
        }
        return true;
    });
}

function avg(arr, sel) {
    if (!arr.length) return 0;
    return arr.reduce((a, o) => a + sel(o), 0) / arr.length;
}

function sum(arr, sel) {
    return arr.reduce((a, o) => a + sel(o), 0);
}

/* ---------- Delta pseudo-determinista vs periodo anterior ---------- */

function pseudoDelta(key, filters) {
    let h = 0;
    const s = key + filters.period + filters.line + filters.country + (filters.rep || '');
    for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
    const raw = (h % 260) / 10 - 13; // rango aprox [-13, +13]
    return round2(raw);
}

function tone(value, floor, warnBand) {
    if (value >= floor) return 'good';
    if (value >= floor - warnBand) return 'warn';
    return 'bad';
}

/* ---------- Construccion de KPIs ---------- */

function commercialKpis(offers, filters) {
    const open = offers.filter((o) => ['Esborrany', 'Presentada', 'Pendent aprovacio'].includes(o.status));
    const accepted = offers.filter((o) => o.status === 'Acceptada');
    const inApproval = offers.filter((o) => o.status === 'Pendent aprovacio');
    const withAddOn = offers.filter((o) => o.addOn);
    const converted = offers.filter((o) => o.converted);
    const monthBookings = sum(accepted, (o) => o.amount);
    const monthTarget = 210000;
    const marginAvg = avg(offers, (o) => o.marginPct);
    const discountAvg = avg(offers, (o) => o.discountPct);
    const quoteAvg = avg(offers, (o) => o.quoteDays);
    const versionsAvg = avg(offers, (o) => o.versions);
    const convRate = offers.length ? (converted.length / offers.length) * 100 : 0;
    const attachRate = offers.length ? (withAddOn.length / offers.length) * 100 : 0;
    const expiring = open.filter((o) => o.ageDays >= 38);

    return [
        { key: 'openOffers', icon: 'standard:quotes', label: 'Les meves ofertes obertes', value: fmtNum(open.length), sub: fmtEur(sum(open, (o) => o.amount)), delta: pseudoDelta('openOffers', filters), tone: 'neutral' },
        { key: 'bookings', icon: 'standard:opportunity', label: 'Bookings del mes', value: fmtEur(monthBookings), sub: `Objectiu ${fmtEur(monthTarget)}`, progress: Math.min(100, Math.round((monthBookings / monthTarget) * 100)), delta: pseudoDelta('bookings', filters), tone: monthBookings >= monthTarget ? 'good' : 'warn' },
        { key: 'conv', icon: 'standard:process', label: 'Conversio oferta -> comanda', value: fmtPct(convRate), sub: `${converted.length} de ${offers.length}`, delta: pseudoDelta('conv', filters), tone: tone(convRate, 30, 10) },
        { key: 'margin', icon: 'standard:coupon_codes', label: 'Marge mitja ofertes', value: fmtPct(marginAvg), sub: `Terra ${MARGIN_FLOOR} %`, delta: pseudoDelta('margin', filters), tone: tone(marginAvg, MARGIN_FLOOR, 6) },
        { key: 'discount', icon: 'standard:promotions', label: 'Descompte mitja aplicat', value: fmtPct(discountAvg), sub: 'Impacte directe al marge', delta: pseudoDelta('discount', filters), tone: discountAvg <= 6 ? 'good' : discountAvg <= 9 ? 'warn' : 'bad' },
        { key: 'quoteTime', icon: 'standard:date_time', label: 'Temps mitja de cotitzacio', value: `${round2(quoteAvg)} dies`, sub: 'De creacio a acceptacio', delta: pseudoDelta('quoteTime', filters), tone: quoteAvg <= 4 ? 'good' : quoteAvg <= 6 ? 'warn' : 'bad' },
        { key: 'pendingAction', icon: 'standard:task', label: 'Pendents de la meva accio', value: fmtNum(open.filter((o) => o.status === 'Esborrany' || o.status === 'Presentada').length), sub: 'Esborranys i presentades', delta: pseudoDelta('pendingAction', filters), tone: 'neutral' },
        { key: 'inApproval', icon: 'standard:approval', label: 'Ofertes en aprovacio', value: fmtNum(inApproval.length), sub: `${fmtEur(sum(inApproval, (o) => o.amount))} bloquejat`, delta: pseudoDelta('inApproval', filters), tone: inApproval.length ? 'warn' : 'good' },
        { key: 'casesNoOffer', icon: 'standard:case', label: 'Casos sense oferta', value: fmtNum(CASES_WITHOUT_OFFER.length), sub: 'Oportunitat latent', delta: pseudoDelta('casesNoOffer', filters), tone: 'warn' },
        { key: 'attach', icon: 'standard:product', label: 'Attach rate add-ons', value: fmtPct(attachRate), sub: 'Ofertes amb add-on', delta: pseudoDelta('attach', filters), tone: tone(attachRate, 30, 10) },
        { key: 'versions', icon: 'standard:record', label: 'Versions mitjanes per oferta', value: `${round2(versionsAvg)}`, sub: 'Renegociacio', delta: pseudoDelta('versions', filters), tone: versionsAvg <= 2 ? 'good' : 'warn' },
        { key: 'expiring', icon: 'standard:events', label: 'Caduquen en 7 dies', value: fmtNum(expiring.length), sub: fmtEur(sum(expiring, (o) => o.amount)), delta: pseudoDelta('expiring', filters), tone: expiring.length ? 'bad' : 'good' }
    ];
}

function managerKpis(offers, filters) {
    const accepted = offers.filter((o) => o.status === 'Acceptada');
    const open = offers.filter((o) => ['Esborrany', 'Presentada', 'Pendent aprovacio'].includes(o.status));
    const inApproval = offers.filter((o) => o.status === 'Pendent aprovacio');
    const converted = offers.filter((o) => o.converted);
    const bookingsYtd = sum(accepted, (o) => o.amount);
    const pipeline = sum(open, (o) => o.amount);
    const weightedPipeline = sum(open, (o) => o.amount * (o.status === 'Pendent aprovacio' ? 0.6 : o.status === 'Presentada' ? 0.4 : 0.2));
    const marginAvg = avg(offers, (o) => o.marginPct);
    const discountAvg = avg(offers, (o) => o.discountPct);
    const targetAvg = 38;
    const erosion = round2(targetAvg - marginAvg);
    const quoteAvg = avg(offers, (o) => o.quoteDays);
    const convRate = offers.length ? (converted.length / offers.length) * 100 : 0;
    const approvalAge = avg(inApproval, (o) => o.ageDays);

    return [
        { key: 'bookingsYtd', icon: 'standard:opportunity', label: 'Bookings YTD', value: fmtEur(bookingsYtd), sub: `Objectiu anual ${fmtEur(ANNUAL_TARGET)}`, progress: Math.min(100, Math.round((bookingsYtd / ANNUAL_TARGET) * 100)), delta: pseudoDelta('bookingsYtd', filters), tone: 'neutral' },
        { key: 'pipeline', icon: 'standard:forecasts', label: 'Pipeline obert', value: fmtEur(pipeline), sub: `Ponderat ${fmtEur(weightedPipeline)}`, delta: pseudoDelta('pipeline', filters), tone: 'neutral' },
        { key: 'convGlobal', icon: 'standard:process', label: 'Conversio global', value: fmtPct(convRate), sub: `${converted.length} comandes`, delta: pseudoDelta('convGlobal', filters), tone: tone(convRate, 30, 10) },
        { key: 'marginBlended', icon: 'standard:coupon_codes', label: 'Marge blended cartera', value: fmtPct(marginAvg), sub: `Objectiu ${targetAvg} %`, delta: pseudoDelta('marginBlended', filters), tone: tone(marginAvg, MARGIN_FLOOR, 6) },
        { key: 'erosion', icon: 'standard:metrics', label: 'Erosio de marge', value: `${round2(erosion)} pp`, sub: 'Objectiu vs real', delta: pseudoDelta('erosion', filters), tone: erosion <= 4 ? 'good' : erosion <= 8 ? 'warn' : 'bad' },
        { key: 'discountPortfolio', icon: 'standard:promotions', label: 'Descompte mitja cartera', value: fmtPct(discountAvg), sub: 'Politica de preus', delta: pseudoDelta('discountPortfolio', filters), tone: discountAvg <= 6 ? 'good' : discountAvg <= 9 ? 'warn' : 'bad' },
        { key: 'quoteTimeMgr', icon: 'standard:date_time', label: 'Temps mitja cotitzacio', value: `${round2(quoteAvg)} dies`, sub: 'Objectiu 4 dies', delta: pseudoDelta('quoteTimeMgr', filters), tone: quoteAvg <= 4 ? 'good' : quoteAvg <= 6 ? 'warn' : 'bad' },
        { key: 'approvalsPending', icon: 'standard:approval', label: 'Aprovacions pendents', value: fmtNum(inApproval.length), sub: `${fmtEur(sum(inApproval, (o) => o.amount))} | ${round2(approvalAge)} d mitjana`, delta: pseudoDelta('approvalsPending', filters), tone: inApproval.length ? 'warn' : 'good' },
        { key: 'installedBase', icon: 'standard:asset_object', label: 'Base instal.lada', value: fmtNum(INSTALLED_BASE.totalMachines), sub: `${INSTALLED_BASE.countries} paisos`, delta: pseudoDelta('installedBase', filters), tone: 'neutral' },
        { key: 'obsolete', icon: 'standard:incident', label: 'Maquines obsoletes', value: fmtNum(INSTALLED_BASE.obsoleteMachines), sub: `${fmtEur(INSTALLED_BASE.obsoletePotential)} potencial`, delta: pseudoDelta('obsolete', filters), tone: 'warn' },
        { key: 'downPayment', icon: 'standard:currency', label: 'Down payment pendent', value: fmtEur(DOWN_PAYMENTS.pendingAmount), sub: `${DOWN_PAYMENTS.pendingOrders} comandes | ${DOWN_PAYMENTS.avgDaysBlocked} d`, delta: pseudoDelta('downPayment', filters), tone: 'bad' },
        { key: 'backlog', icon: 'standard:work_order', label: 'Backlog intervencio', value: `${fmtNum(INTERVENTION_BACKLOG.committedHours)} h`, sub: `${round2(INTERVENTION_BACKLOG.weeksLoad)} setmanes de carrega`, delta: pseudoDelta('backlog', filters), tone: 'neutral' }
    ];
}

/* ---------- Graficos ---------- */

function familyMarginChart(offers) {
    return FAMILIES.map((f) => {
        const subset = offers.filter((o) => o.family === f.code);
        const m = subset.length ? avg(subset, (o) => o.marginPct) : f.target * 0.9;
        return {
            key: f.code,
            label: f.label,
            marginPct: round2(m),
            target: f.target,
            valueLabel: fmtPct(m),
            barWidth: Math.min(100, Math.round((m / 50) * 100)),
            barClass: m >= f.target ? 'bar bar-green' : m >= MARGIN_FLOOR ? 'bar bar-yellow' : 'bar bar-red'
        };
    });
}

function linePipelineChart(offers) {
    // Mismos acentos por familia que las imagenes de catalogo (COMEXI_ProductImages).
    const palette = { T: '#ed1848', L: '#b01136', C: '#7a142e' };
    const totals = LINES.map((l) => ({
        key: l.code,
        label: l.label,
        amount: sum(offers.filter((o) => o.line === l.code), (o) => o.amount),
        color: palette[l.code]
    }));
    const grand = totals.reduce((a, t) => a + t.amount, 0) || 1;
    let acc = 0;
    const segments = totals.map((t) => {
        const pct = (t.amount / grand) * 100;
        const from = acc;
        acc += pct;
        return { ...t, pct: round2(pct), pctLabel: fmtPct(pct), amountLabel: fmtEur(t.amount), from: round2(from), to: round2(acc), color: t.color };
    });
    const gradient = segments.map((s) => `${s.color} ${s.from}% ${s.to}%`).join(', ');
    return { segments, gradient: `conic-gradient(${gradient})`, totalLabel: fmtEur(grand) };
}

function countryPipelineChart(offers) {
    const rows = COUNTRIES.map((c) => ({
        key: c.code,
        label: c.label,
        hasRep: c.hasRep,
        amount: sum(offers.filter((o) => o.country === c.code), (o) => o.amount)
    })).filter((r) => r.amount > 0).sort((a, b) => b.amount - a.amount);
    const max = rows.length ? rows[0].amount : 1;
    return rows.map((r) => ({
        ...r,
        amountLabel: fmtEur(r.amount),
        barWidth: Math.max(4, Math.round((r.amount / max) * 100)),
        repBadge: r.hasRep ? 'Rep 8%' : ''
    }));
}

/**
 * Primera etapa del embudo: la demanda de retrofit que entra por servicio. Se cruza
 * cada caso con la campana de obsolescencia para arrastrar el modelo y el componente
 * obsoleto de la maquina, y el expediente del guion se coloca primero porque es el que
 * el comercial abre en la demo.
 */
function retrofitCases(filters) {
    const byAsset = INSTALLED_BASE.campaign.reduce((m, c) => ({ ...m, [c.asset]: c }), {});
    return CASES_WITHOUT_OFFER
        .filter((c) => filters.line === 'all' || c.line === filters.line)
        .filter((c) => filters.country === 'all' || c.country === filters.country)
        .map((c) => {
            const machine = byAsset[c.asset] || {};
            return {
                ...c,
                key: c.id,
                model: machine.model || '',
                component: machine.component || '',
                potential: machine.potential || 0,
                potentialLabel: machine.potential ? fmtEur(machine.potential) : '',
                lineLabel: LINE_LABELS[c.line] || c.line,
                countryLabel: COUNTRY_LABELS[c.country] || c.country,
                isAnchor: c.id === ANCHOR_CASE_ID
            };
        })
        .sort((a, b) => (b.isAnchor ? 1 : 0) - (a.isAnchor ? 1 : 0) || a.ageDays - b.ageDays);
}

function funnelChart(offers, filters) {
    const stages = [
        { key: 'retrofit', label: 'Assets / Casos retrofit', count: retrofitCases(filters).length },
        { key: 'offers', label: 'Ofertes', count: offers.length },
        { key: 'presented', label: 'Presentades', count: offers.filter((o) => o.stage === 'Presentada' || o.status === 'Acceptada').length },
        { key: 'accepted', label: 'Acceptades', count: offers.filter((o) => o.status === 'Acceptada').length },
        { key: 'orders', label: 'Comandes', count: offers.filter((o) => o.converted).length }
    ];
    // El ancho es relativo a la etapa mas alta, no a la primera: con el filtro anual las
    // ofertas superan a los casos de retrofit y la barra se saldria del panel.
    const max = Math.max(...stages.map((s) => s.count), 1);
    return stages.map((s) => ({ ...s, barWidth: Math.max(6, Math.round((s.count / max) * 100)) }));
}

function trendChart(offers, period) {
    const [minM, maxM] = periodMonthRange(period);
    const months = [];
    let maxBookings = 1;
    for (let m = minM; m <= maxM; m++) {
        const subset = offers.filter((o) => o.monthIdx === m && o.status === 'Acceptada');
        const bookings = sum(subset, (o) => o.amount);
        const marginPct = subset.length ? avg(subset, (o) => o.marginPct) : 0;
        maxBookings = Math.max(maxBookings, bookings);
        months.push({ key: MONTHS[m], label: MONTHS[m], bookings, marginPct: round2(marginPct) });
    }
    return months.map((m) => ({
        ...m,
        bookingsLabel: fmtEurK(m.bookings),
        marginLabel: fmtPct(m.marginPct),
        barHeight: Math.max(6, Math.round((m.bookings / maxBookings) * 100))
    }));
}

function repRanking(offers) {
    const rows = REPS.map((rep) => {
        const subset = offers.filter((o) => o.rep === rep);
        const accepted = subset.filter((o) => o.status === 'Acceptada');
        return {
            key: rep,
            rep,
            bookings: sum(accepted, (o) => o.amount),
            marginPct: subset.length ? round2(avg(subset, (o) => o.marginPct)) : 0,
            discountPct: subset.length ? round2(avg(subset, (o) => o.discountPct)) : 0,
            offers: subset.length
        };
    }).sort((a, b) => b.bookings - a.bookings);
    return rows.map((r, i) => ({
        ...r,
        rank: i + 1,
        bookingsLabel: fmtEur(r.bookings),
        marginLabel: fmtPct(r.marginPct),
        discountLabel: fmtPct(r.discountPct),
        marginTone: r.marginPct >= MARGIN_FLOOR ? 'pill pill-good' : 'pill pill-bad'
    }));
}

/* ---------- Tablas ---------- */

const LINE_LABELS = LINES.reduce((m, l) => ({ ...m, [l.code]: l.label }), {});
const COUNTRY_LABELS = COUNTRIES.reduce((m, c) => ({ ...m, [c.code]: c.label }), {});

function decorateOffer(o) {
    return {
        ...o,
        monthLabel: MONTHS[o.monthIdx],
        lineLabel: LINE_LABELS[o.line] || o.line,
        countryLabel: COUNTRY_LABELS[o.country] || o.country,
        amountLabel: fmtEur2(o.amount),
        marginLabel: fmtPct(o.marginPct),
        discountLabel: fmtPct(o.discountPct),
        marginTone: o.marginPct >= MARGIN_FLOOR ? 'pill pill-good' : o.marginPct >= MARGIN_FLOOR - 6 ? 'pill pill-warn' : 'pill pill-bad',
        statusTone: o.status === 'Acceptada' ? 'badge badge-good' : o.status === 'Pendent aprovacio' ? 'badge badge-warn' : o.status === 'Rebutjada' ? 'badge badge-bad' : 'badge badge-neutral',
        ageLabel: `${o.ageDays} d`,
        rowClass: o.isAnchor ? 'data-row anchor-row' : 'data-row'
    };
}

function activeOffersTable(offers) {
    return offers
        .filter((o) => ['Esborrany', 'Presentada', 'Pendent aprovacio'].includes(o.status))
        .sort((a, b) => (b.isAnchor ? 1 : 0) - (a.isAnchor ? 1 : 0) || b.amount - a.amount)
        .slice(0, 12)
        .map(decorateOffer);
}

function approvalQueue(offers) {
    return offers
        .filter((o) => o.status === 'Pendent aprovacio')
        .sort((a, b) => (b.isAnchor ? 1 : 0) - (a.isAnchor ? 1 : 0) || a.marginPct - b.marginPct)
        .map(decorateOffer);
}

function marginRiskTable(offers) {
    return offers
        .filter((o) => o.marginPct < MARGIN_FLOOR && o.status !== 'Rebutjada')
        .sort((a, b) => a.marginPct - b.marginPct)
        .slice(0, 8)
        .map(decorateOffer);
}

/* ---------- API publica ---------- */

export const ROLE_OPTIONS = [
    { label: 'Comercial de servei', value: 'commercial' },
    { label: 'Cap de servei', value: 'manager' }
];

export const PERIOD_OPTIONS = [
    { label: 'Aquest mes', value: 'month' },
    { label: 'Trimestre', value: 'quarter' },
    { label: 'Any en curs (YTD)', value: 'ytd' },
    { label: 'Ultims 12 mesos', value: '12m' }
];

export const LINE_OPTIONS = [
    { label: 'Totes les linies', value: 'all' },
    ...LINES.map((l) => ({ label: l.label, value: l.code }))
];

export const COUNTRY_OPTIONS = [
    { label: 'Tots els paisos', value: 'all' },
    ...COUNTRIES.map((c) => ({ label: c.label, value: c.code }))
];

export const REP_OPTIONS = [
    { label: 'Tots els comercials', value: 'all' },
    ...REPS.map((r) => ({ label: r, value: r }))
];

export const ANCHOR = {
    caseId: ANCHOR_CASE_ID,
    offerId: ANCHOR_OFFER.id,
    account: ANCHOR_OFFER.account,
    asset: ANCHOR_OFFER.asset,
    amountLabel: fmtEur2(ANCHOR_OFFER.amount),
    marginLabel: fmtPct(ANCHOR_OFFER.marginPct),
    waterfall: ANCHOR_WATERFALL.map((w) => ({
        ...w,
        valueLabel: fmtEur2(w.value),
        rowClass: `wf-row wf-${w.kind}`,
        isPositive: w.value >= 0
    }))
};

export const CAMPAIGN = INSTALLED_BASE.campaign.map((c) => ({
    ...c,
    potentialLabel: fmtEur(c.potential)
}));

export const CASES = CASES_WITHOUT_OFFER;

export const CONSTANTS = { MARGIN_FLOOR, CURRENT_COMMERCIAL };

/**
 * Punto de entrada: devuelve el dashboard completo para un rol y un set de filtros.
 * Todos los KPIs y graficos se recalculan agregando sobre el universo filtrado.
 */
export function getDashboardData(role, filters) {
    const offers = filterOffers(role, filters);
    const isManager = role === 'manager';

    return {
        role,
        offerCount: offers.length,
        offers: offers.map(decorateOffer),
        kpis: isManager ? managerKpis(offers, filters) : commercialKpis(offers, filters),
        familyMargin: familyMarginChart(offers),
        linePipeline: linePipelineChart(offers),
        countryPipeline: countryPipelineChart(offers),
        funnel: funnelChart(offers, filters),
        trend: trendChart(offers, filters.period),
        repRanking: isManager ? repRanking(offers) : [],
        activeOffers: activeOffersTable(offers),
        approvalQueue: approvalQueue(offers),
        marginRisk: isManager ? marginRiskTable(offers) : [],
        cases: CASES_WITHOUT_OFFER,
        retrofitCases: retrofitCases(filters)
    };
}
