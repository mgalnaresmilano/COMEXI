import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRetrofitNavTargets from '@salesforce/apex/COMEXI_AssetOverviewController.getRetrofitNavTargets';
import {
    getDashboardData,
    ROLE_OPTIONS,
    PERIOD_OPTIONS,
    LINE_OPTIONS,
    COUNTRY_OPTIONS,
    REP_OPTIONS,
    ANCHOR,
    CAMPAIGN,
    CONSTANTS
} from './mockData';

const EUR2 = new Intl.NumberFormat('es-ES', { style: 'currency', currency: 'EUR', minimumFractionDigits: 2, maximumFractionDigits: 2 });
const PCT = new Intl.NumberFormat('es-ES', { maximumFractionDigits: 2 });

export default class ComexiRevenueDashboard extends NavigationMixin(LightningElement) {
    @api cardTitle = 'Comexi Revenue Cloud - Panell de servei i retrofit';
    @api defaultRole = 'manager';

    @track role = 'manager';
    @track filters = { period: 'ytd', line: 'all', country: 'all', rep: 'all' };
    @track data = null;

    isLoading = false;
    lastRefresh = '';
    resolvedIds = new Set();
    suppressAnim = false;

    // drill-down y modales
    drilldown = null;
    showWaterfall = false;
    waterfall = null;
    waterfallTitle = '';
    showCampaign = false;
    showDetail = false;
    detailTitle = '';
    detailSubtitle = '';
    @track detailRows = [];
    showRetrofit = false;
    retrofitSubtitle = '';
    @track retrofitRows = [];

    roleOptions = ROLE_OPTIONS;
    periodOptions = PERIOD_OPTIONS;
    lineOptions = LINE_OPTIONS;
    countryOptions = COUNTRY_OPTIONS;
    repOptions = REP_OPTIONS;
    campaign = CAMPAIGN;

    connectedCallback() {
        this.role = this.defaultRole === 'commercial' ? 'commercial' : 'manager';
        this.recompute();
        this.stampRefresh();
    }

    /* ---------- Estado derivado ---------- */

    get bodyClass() {
        return this.suppressAnim ? 'dashboard-body no-anim' : 'dashboard-body';
    }

    get isManager() {
        return this.role === 'manager';
    }

    get isCommercial() {
        return this.role === 'commercial';
    }

    get roleLabel() {
        return this.isManager ? 'Cap de servei' : 'Comercial de servei';
    }

    get commercialTabClass() {
        return this.isCommercial ? 'role-tab is-selected' : 'role-tab';
    }

    get managerTabClass() {
        return this.isManager ? 'role-tab is-selected' : 'role-tab';
    }

    get kpis() {
        if (!this.data) return [];
        return this.data.kpis.map((k) => {
            const up = k.delta > 0;
            const flat = !k.delta || Math.abs(k.delta) < 0.05;
            return {
                ...k,
                cardClass: `metric-card tone-${k.tone}${this.drilldown === k.key ? ' is-active' : ''}`,
                iconWrapClass: `metric-icon tone-${k.tone}`,
                deltaLabel: flat ? '=' : `${up ? '\u25B2' : '\u25BC'} ${PCT.format(Math.abs(k.delta))} %`,
                deltaClass: flat ? 'metric-delta flat' : up ? 'metric-delta up' : 'metric-delta down',
                showProgress: typeof k.progress === 'number',
                progressStyle: `width:${k.progress}%`
            };
        });
    }

    get familyMargin() {
        return this.data ? this.data.familyMargin : [];
    }

    get lineSegments() {
        return this.data ? this.data.linePipeline.segments.map((s) => ({ ...s, swatchStyle: `background:${s.color}` })) : [];
    }

    get donutSegments() {
        if (!this.data) return [];
        return this.data.linePipeline.segments.map((s) => ({
            key: s.key,
            label: s.label,
            color: s.color,
            amountLabel: s.amountLabel,
            pctLabel: s.pctLabel,
            dasharray: `${s.pct} ${100 - s.pct}`,
            dashoffset: `${(25 - s.from + 100) % 100}`
        }));
    }

    get lineTotalLabel() {
        return this.data ? this.data.linePipeline.totalLabel : '';
    }

    get countryPipeline() {
        return this.data ? this.data.countryPipeline.map((c) => ({ ...c, barStyle: `width:${c.barWidth}%` })) : [];
    }

    get funnel() {
        if (!this.data) return [];
        return this.data.funnel.map((f) => ({
            ...f,
            barStyle: `width:${f.barWidth}%`,
            hint: f.key === 'retrofit'
                ? 'Clic per veure les maquines i els casos de retrofit'
                : 'Clic per veure les ofertes'
        }));
    }

    get trend() {
        return this.data ? this.data.trend.map((t) => ({ ...t, barStyle: `height:${t.barHeight}%` })) : [];
    }

    get repRanking() {
        return this.data ? this.data.repRanking : [];
    }

    get activeOffers() {
        return this.data ? this.data.activeOffers : [];
    }

    get approvalQueue() {
        return this.data ? this.data.approvalQueue.filter((o) => !this.resolvedIds.has(o.id)) : [];
    }

    get marginRisk() {
        return this.data ? this.data.marginRisk : [];
    }

    get cases() {
        return this.data ? this.data.cases : [];
    }

    get hasApprovals() {
        return this.approvalQueue.length > 0;
    }

    get familyMarginDecorated() {
        return this.familyMargin.map((f) => ({ ...f, barStyle: `width:${f.barWidth}%` }));
    }

    /* ---------- Handlers ---------- */

    handleRoleChange(event) {
        this.role = event.detail.value;
        this.drilldown = null;
        this.recompute();
    }

    handleRoleTab(event) {
        this.role = event.currentTarget.dataset.role;
        this.drilldown = null;
        this.recompute();
        this.replayAnim();
    }

    handleFilter(event) {
        const key = event.target.dataset.filter;
        this.filters = { ...this.filters, [key]: event.detail.value };
        this.recompute();
        this.replayAnim();
    }

    replayAnim() {
        this.suppressAnim = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.suppressAnim = false;
        }, 20);
    }

    handleRefresh() {
        this.isLoading = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.recompute();
            this.stampRefresh();
            this.isLoading = false;
            this.replayAnim();
            this.toast('Panell actualitzat', `Dades recalculades a les ${this.lastRefresh}`, 'success');
        }, 650);
    }

    handleTileClick(event) {
        const key = event.currentTarget.dataset.key;
        this.drilldown = this.drilldown === key ? null : key;
    }

    get drilldownInfo() {
        if (!this.drilldown || !this.data) return null;
        const k = this.data.kpis.find((x) => x.key === this.drilldown);
        if (!k) return null;
        return { label: k.label, value: k.value, sub: k.sub };
    }

    handleRowClick(event) {
        const id = event.currentTarget.dataset.id;
        this.openWaterfall(id);
    }

    openWaterfall(id) {
        if (id === ANCHOR.offerId) {
            this.waterfall = ANCHOR.waterfall;
            this.waterfallTitle = `Escandall ${ANCHOR.offerId} - ${ANCHOR.account}`;
        } else {
            const offer = this.findOffer(id);
            if (!offer) return;
            this.waterfall = this.buildWaterfall(offer);
            this.waterfallTitle = `Escandall ${offer.id} - ${offer.account}`;
        }
        this.showWaterfall = true;
    }

    findOffer(id) {
        if (!this.data) return null;
        return (
            this.data.activeOffers.find((o) => o.id === id) ||
            this.data.approvalQueue.find((o) => o.id === id) ||
            this.data.marginRisk.find((o) => o.id === id)
        );
    }

    buildWaterfall(offer) {
        const cost = offer.cost;
        const listPrice = offer.discountPct > 0 ? offer.amount / (1 - offer.discountPct / 100) : offer.amount;
        const warranty = cost * 0.026;
        const ralf = cost * 0.03;
        const margin = listPrice - cost - warranty - ralf;
        const discount = offer.amount - listPrice;
        const rows = [
            { label: 'Cost material + hores', value: cost, kind: 'base' },
            { label: 'Uplift garantia 2,60%', value: warranty, kind: 'add' },
            { label: 'Uplift RALF 3,00%', value: ralf, kind: 'add' },
            { label: 'Marge', value: margin, kind: 'margin' },
            { label: 'Preu de venda', value: listPrice, kind: 'subtotal' },
            { label: `Descompte -${PCT.format(offer.discountPct)} %`, value: discount, kind: 'discount' },
            { label: 'Preu final', value: offer.amount, kind: 'total' }
        ];
        return rows.map((r) => ({
            ...r,
            valueLabel: EUR2.format(r.value),
            rowClass: `wf-row wf-${r.kind}`,
            isPositive: r.value >= 0
        }));
    }

    closeWaterfall() {
        this.showWaterfall = false;
        this.waterfall = null;
    }

    handleApprove(event) {
        this.resolveApproval(event.currentTarget.dataset.id, true);
    }

    handleReject(event) {
        this.resolveApproval(event.currentTarget.dataset.id, false);
    }

    resolveApproval(id, approved) {
        this.resolvedIds = new Set([...this.resolvedIds, id]);
        this.toast(
            approved ? 'Oferta aprovada' : 'Oferta rebutjada',
            `${id} ${approved ? 'aprovada' : 'rebutjada'} amb traca completa (data, persona i motiu).`,
            approved ? 'success' : 'warning'
        );
    }

    handleCreateOffer(event) {
        const caseId = event.currentTarget.dataset.id;
        this.toast('Nova oferta', `S'ha creat l'oportunitat de retrofit des del cas ${caseId}.`, 'success');
    }

    handleNewOffer() {
        this.toast('Nova oferta', "S'obre el configurador de retrofit T100.", 'info');
    }

    handleExport() {
        this.toast('Exportacio', "S'ha generat l'informe del panell en PDF.", 'success');
    }

    openCampaign() {
        this.showCampaign = true;
    }

    closeCampaign() {
        this.showCampaign = false;
    }

    /* ---------- Clic en graficos: ver los datos detras ---------- */

    handleChartClick(event) {
        const el = event.currentTarget;
        const dim = el.dataset.dim;
        const key = el.dataset.key;
        const label = el.dataset.label || key;
        const offers = this.data ? this.data.offers : [];
        let rows = [];
        let prefix = '';
        if (dim === 'family') {
            rows = offers.filter((o) => o.family === key);
            prefix = 'Familia';
        } else if (dim === 'line') {
            rows = offers.filter((o) => o.line === key);
            prefix = 'Linia';
        } else if (dim === 'country') {
            rows = offers.filter((o) => o.country === key);
            prefix = 'Pais';
        } else if (dim === 'month') {
            rows = offers.filter((o) => o.monthLabel === key);
            prefix = 'Mes';
        }
        this.openDetail(`${prefix}: ${label}`, rows);
    }

    handleFunnelClick(event) {
        const key = event.currentTarget.dataset.key;
        const label = event.currentTarget.dataset.label || key;
        // La primera etapa no son ofertas, son casos de servicio: tiene su propio modal
        // porque es el punto de entrada a la maquina y al caso reales.
        if (key === 'retrofit') {
            this.openRetrofitDetail();
            return;
        }
        const offers = this.data ? this.data.offers : [];
        let rows;
        if (key === 'accepted') rows = offers.filter((o) => o.status === 'Acceptada');
        else if (key === 'orders') rows = offers.filter((o) => o.converted);
        else if (key === 'presented') rows = offers.filter((o) => o.stage === 'Presentada' || o.status === 'Acceptada');
        else rows = offers;
        this.openDetail(`Embut: ${label}`, rows);
    }

    openDetail(title, rows) {
        this.detailTitle = title;
        this.detailRows = rows;
        this.detailSubtitle = `${rows.length} ofertes · ${this.formatEurSum(rows)}`;
        this.showDetail = true;
    }

    closeDetail() {
        this.showDetail = false;
        this.detailRows = [];
    }

    formatEurSum(rows) {
        const total = rows.reduce((a, o) => a + o.amount, 0);
        return new Intl.NumberFormat('es-ES', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(total);
    }

    get hasDetailRows() {
        return this.detailRows && this.detailRows.length > 0;
    }

    /* ---------- Etapa de retrofit: del embudo a la maquina real ---------- */

    /**
     * El parque de maquinas del panel es mock, pero la maquina del guion existe en la
     * org. Se abre el modal con las filas del mock y se pregunta al Apex cuales de esos
     * numeros de serie tienen registro: solo esas quedan clicables.
     */
    openRetrofitDetail() {
        const rows = this.data ? this.data.retrofitCases : [];
        this.retrofitRows = rows.map((r) => this.decorateRetrofitRow(r, null));
        this.retrofitSubtitle = `${rows.length} casos de servei sense oferta`;
        this.showRetrofit = true;
        if (!rows.length) return;

        getRetrofitNavTargets({ serialNumbers: rows.map((r) => r.asset) })
            .then((targets) => {
                const bySerial = (targets || []).reduce((m, t) => ({ ...m, [t.serial]: t }), {});
                this.retrofitRows = rows.map((r) => this.decorateRetrofitRow(r, bySerial[r.asset]));
                const live = this.retrofitRows.filter((r) => r.isLive).length;
                this.retrofitSubtitle = `${rows.length} casos de servei sense oferta · ${live} amb registre a l'org`;
            })
            .catch(() => {
                /* Sin resolucion las filas se quedan en texto plano. El panel no se rompe
                   por no poder traducir un numero de serie a un Id. */
            });
    }

    decorateRetrofitRow(row, target) {
        const isLive = !!(target && target.assetId);
        return {
            ...row,
            // En la fila resuelta manda el modelo de la org, no el del mock.
            model: (target && target.model) || row.model,
            assetId: isLive ? target.assetId : null,
            caseRecordId: target && target.caseId ? target.caseId : null,
            // El expediente es lo que el cliente reconoce; el CaseNumber de la org va en
            // el tooltip, que es la prueba de que el caso existe de verdad.
            caseHint: target && target.caseNumber
                ? `Obrir el cas ${target.caseNumber} de l'org`
                : 'Obrir el cas de servei',
            rowClass: row.isAnchor ? 'data-row is-anchor' : 'data-row',
            isLive,
            hasCaseRecord: !!(target && target.caseId)
        };
    }

    closeRetrofit() {
        this.showRetrofit = false;
        this.retrofitRows = [];
    }

    get hasRetrofitRows() {
        return this.retrofitRows && this.retrofitRows.length > 0;
    }

    handleOpenAsset(event) {
        const row = this.findRetrofitRow(event.currentTarget.dataset.id);
        if (!row || !row.assetId) {
            this.notSynced(event.currentTarget.dataset.id);
            return;
        }
        this.navigateToRecord(row.assetId);
    }

    handleOpenCase(event) {
        const row = this.findRetrofitRow(event.currentTarget.dataset.id);
        if (!row || !row.caseRecordId) {
            this.notSynced(event.currentTarget.dataset.id);
            return;
        }
        this.navigateToRecord(row.caseRecordId);
    }

    findRetrofitRow(caseId) {
        return this.retrofitRows.find((r) => r.id === caseId);
    }

    navigateToRecord(recordId) {
        this.showRetrofit = false;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    notSynced(caseId) {
        this.toast(
            'Maquina no sincronitzada',
            `El cas ${caseId} es una dada de demostracio i encara no te registre en aquesta org.`,
            'info'
        );
    }

    handleCampaignFromTile(event) {
        // permite abrir la campana desde el tile de obsolescencia
        if (event) event.stopPropagation();
        this.showCampaign = true;
    }

    /* ---------- Helpers ---------- */

    recompute() {
        this.data = getDashboardData(this.role, this.filters);
    }

    stampRefresh() {
        const now = new Date();
        this.lastRefresh = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get marginFloorLabel() {
        return `${CONSTANTS.MARGIN_FLOOR} %`;
    }
}
