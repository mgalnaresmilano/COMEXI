import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getAssetOverview from '@salesforce/apex/COMEXI_AssetOverviewController.getAssetOverview';
import { LIFECYCLE, OPERATING } from './mockData';

const RISK_TONE = {
    Critico: 'bad',
    Alto: 'bad',
    Medio: 'warn',
    Bajo: 'good'
};

const SERVICE_TONE = {
    Gold: 'accent',
    Silver: 'neutral',
    Bronze: 'neutral',
    'Sin contrato': 'warn'
};

export default class ComexiAssetMachineCard extends NavigationMixin(LightningElement) {
    @api recordId;

    overview;
    loadError;
    operating = OPERATING;

    @wire(getAssetOverview, { assetId: '$recordId' })
    wiredOverview({ data, error }) {
        if (data) {
            this.overview = data;
            this.loadError = undefined;
        } else if (error) {
            this.loadError = this.readError(error);
            this.overview = undefined;
        }
    }

    // ── Estado de carga ──────────────────────────────────────────────────────────

    get isLoading() {
        return !this.overview && !this.loadError;
    }

    get machine() {
        return this.overview ? this.overview.machine : undefined;
    }

    get hasMachine() {
        return !!this.machine;
    }

    // ── Cabecera e identificacion ────────────────────────────────────────────────

    get headline() {
        const m = this.machine;
        if (!m) return '';
        return m.model || m.productName || m.name;
    }

    get hasImage() {
        return !!(this.machine && this.machine.imageUrl);
    }

    /** La placa de identificacion: lo que un tecnico leeria en el chasis. */
    get plate() {
        const m = this.machine;
        if (!m) return [];
        return [
            { id: 'serial', label: 'Numero de serie', value: m.serialNumber || m.name },
            { id: 'year', label: 'Ano de instalacion', value: m.installYear ? String(m.installYear) : '-' },
            { id: 'line', label: 'Linea', value: m.line || '-' },
            { id: 'control', label: 'Sistema de control', value: m.controlSystem || '-' },
            { id: 'site', label: 'Emplazamiento', value: m.siteLocation || m.accountName || '-' },
            { id: 'sap', label: 'Codigo SAP', value: m.sapEquipmentCode || '-' }
        ];
    }

    /** Ficha tecnica en una linea: es el argumento de "esto ya no es una celda". */
    get specs() {
        const m = this.machine;
        if (!m) return [];
        const rows = [];
        if (m.webWidthMm) rows.push({ id: 'width', label: 'Ancho de banda', value: `${m.webWidthMm} mm` });
        if (m.stations) rows.push({ id: 'stations', label: 'Estaciones', value: String(m.stations) });
        if (m.maxSpeedMpm) rows.push({ id: 'speed', label: 'Velocidad max.', value: `${m.maxSpeedMpm} m/min` });
        rows.push({ id: 'shifts', label: 'Regimen', value: this.operating.shifts });
        return rows;
    }

    // ── KPIs ─────────────────────────────────────────────────────────────────────

    get kpis() {
        const m = this.machine;
        if (!m) return [];
        return [
            {
                id: 'age',
                label: 'Antiguedad',
                value: m.ageYears != null ? String(m.ageYears) : '-',
                unit: m.ageYears != null ? 'anos' : '',
                tone: 'neutral'
            },
            {
                id: 'hours',
                label: 'Horas de funcionamiento',
                value: m.operatingHours != null ? this.thousands(m.operatingHours) : '-',
                unit: 'h',
                tone: 'neutral'
            },
            {
                id: 'interventions',
                label: 'Intervenciones',
                value: m.interventionCount != null ? String(m.interventionCount) : '-',
                unit: '',
                tone: 'neutral'
            },
            {
                id: 'revenue',
                label: 'Servicio acumulado',
                value: m.serviceRevenueLifetime != null ? this.money(m.serviceRevenueLifetime) : '-',
                unit: m.currencyCode || 'EUR',
                tone: 'accent'
            }
        ].map((k) => ({ ...k, tileClass: `kpi kpi-${k.tone}` }));
    }

    // ── Banda de obsolescencia ───────────────────────────────────────────────────

    get showObsolescence() {
        const m = this.machine;
        return !!(m && (m.osInstalled || m.obsoleteComponent || m.obsolescenceRisk));
    }

    get obsolescence() {
        const m = this.machine;
        if (!m) return undefined;
        const tone = RISK_TONE[m.obsolescenceRisk] || 'neutral';
        return {
            os: m.osInstalled || 'No informado',
            supportEnd: m.osSupportEnd,
            hasSupportEnd: !!m.osSupportEnd,
            component: m.obsoleteComponent,
            risk: m.obsolescenceRisk || 'Sin evaluar',
            riskClass: `badge badge-${tone}`,
            bandClass: `obsolescence obsolescence-${tone}`,
            /* El fin de soporte ya pasado es lo que convierte un aviso en una venta:
               se enuncia distinto segun este por delante o por detras de hoy. */
            supportLabel: m.osOutOfSupport ? 'Fuera de soporte desde' : 'Soporte hasta'
        };
    }

    /** Veredicto de viabilidad: es la antesala del Advisor de la escena 02. */
    get viability() {
        const m = this.machine;
        if (!m) return undefined;
        if (!m.retrofitEligible) {
            return {
                label: 'No elegible para retrofit estandar',
                detail: 'La salida de esta maquina es sustitucion, no retrofit.',
                pillClass: 'pill pill-bad',
                iconName: 'utility:close'
            };
        }
        if (m.requiresEngineering) {
            return {
                label: 'Elegible, requiere ingenieria',
                detail: 'El retrofit es posible pero tiene que pasar por ingenieria de proyecto.',
                pillClass: 'pill pill-warn',
                iconName: 'utility:warning'
            };
        }
        return {
            label: 'Elegible sin ingenieria',
            detail: m.recommendedSku
                ? `Retrofit recomendado ${m.recommendedSku}. Trabajo de campo, sin ingenieria de proyecto.`
                : 'Trabajo de campo, sin ingenieria de proyecto.',
            pillClass: 'pill pill-good',
            iconName: 'utility:check'
        };
    }

    get serviceBadge() {
        const m = this.machine;
        if (!m || !m.serviceLevel) return undefined;
        const tone = SERVICE_TONE[m.serviceLevel] || 'neutral';
        return { label: m.serviceLevel, badgeClass: `badge badge-${tone}` };
    }

    // ── Componentes ──────────────────────────────────────────────────────────────

    get components() {
        const list = (this.overview && this.overview.components) || [];
        return list.map((c) => ({
            ...c,
            rowClass: c.atRisk ? 'component-row is-at-risk' : 'component-row',
            badgeLabel: c.atRisk ? 'En riesgo' : 'Soportado',
            badgeClass: c.atRisk ? 'badge badge-bad' : 'badge badge-good'
        }));
    }

    get hasComponents() {
        return this.components.length > 0;
    }

    get componentsSummary() {
        const total = this.components.length;
        const atRisk = this.components.filter((c) => c.atRisk).length;
        if (!total) return '';
        return atRisk
            ? `${total} componentes trazados, ${atRisk} en riesgo por obsolescencia.`
            : `${total} componentes trazados, ninguno en riesgo.`;
    }

    // ── Historial ────────────────────────────────────────────────────────────────

    get lifecycle() {
        return LIFECYCLE.map((e) => ({
            ...e,
            markerClass: `timeline-marker marker-${e.kind}`,
            iconName: {
                install: 'utility:setup_assistant_guide',
                service: 'utility:wrench',
                retrofit: 'utility:upload',
                alert: 'utility:warning'
            }[e.kind]
        }));
    }

    get caseRows() {
        const list = (this.overview && this.overview.cases) || [];
        return list.map((c) => ({
            ...c,
            statusClass: c.isClosed ? 'badge badge-neutral' : 'badge badge-warn',
            label: c.reference ? `${c.reference}` : c.caseNumber
        }));
    }

    get hasCases() {
        return this.caseRows.length > 0;
    }

    get casesSummary() {
        const total = this.caseRows.length;
        const open = (this.overview && this.overview.openCaseCount) || 0;
        return `${total} casos sobre esta maquina, ${open} abiertos.`;
    }

    get retrofitHistory() {
        const m = this.machine;
        if (!m || !m.retrofitsApplied) return undefined;
        return {
            skus: m.retrofitsApplied,
            lastDate: m.lastRetrofitDate,
            hasLastDate: !!m.lastRetrofitDate
        };
    }

    get potentialValue() {
        const m = this.machine;
        if (!m || m.retrofitPotentialValue == null) return undefined;
        return `${this.money(m.retrofitPotentialValue)} ${m.currencyCode || 'EUR'}`;
    }

    // ── Navegacion ───────────────────────────────────────────────────────────────

    handleOpenAccount() {
        this.navigate(this.machine && this.machine.accountId);
    }

    handleOpenComponent(event) {
        this.navigate(event.currentTarget.dataset.id);
    }

    handleOpenCase(event) {
        this.navigate(event.currentTarget.dataset.id);
    }

    navigate(recordId) {
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    // ── Utilidades ───────────────────────────────────────────────────────────────

    thousands(value) {
        return Number(value).toLocaleString('es-ES');
    }

    money(value) {
        return Number(value).toLocaleString('es-ES', {
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        });
    }

    readError(error) {
        if (!error) return 'Error desconocido.';
        if (error.body && error.body.message) return error.body.message;
        if (Array.isArray(error.body) && error.body.length) return error.body[0].message;
        return error.message || String(error);
    }
}
