import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCaseBriefing from '@salesforce/apex/COMEXI_RetrofitAdvisorController.getCaseBriefing';
import createRetrofitOpportunityAndQuote from '@salesforce/apex/COMEXI_RetrofitAdvisorController.createRetrofitOpportunityAndQuote';
import refreshQuoteMargins from '@salesforce/apex/COMEXI_RetrofitAdvisorController.refreshQuoteMargins';
import resetDemoState from '@salesforce/apex/COMEXI_RetrofitAdvisorController.resetDemoState';
import { RELATED_CASES, AGENT_STAGES, RECOMMENDATION } from './mockData';

const STAGE_MS = 700;
/* El pricing de Place Sales Transaction puede seguir corriendo cuando la llamada ya ha
   devuelto, asi que se pide un segundo sellado de margenes poco despues. */
const MARGIN_RECHECK_MS = 2500;

export default class ComexiCaseRetrofitAdvisor extends NavigationMixin(LightningElement) {
    @api recordId;

    briefing;
    loadError;

    phase = 'briefing';
    stageIndex = -1;
    creating = false;
    resetting = false;
    confirmingReset = false;
    result;
    createError;

    recommendation = RECOMMENDATION;
    relatedCases = RELATED_CASES;

    _timers = [];
    _wired;

    @wire(getCaseBriefing, { caseId: '$recordId' })
    wiredBriefing(result) {
        /* Se guarda el resultado del wire para poder refrescarlo tras el reinicio:
           getCaseBriefing es cacheable, asi que sin refreshApex el componente seguiria
           viendo el existingQuoteId de una oferta ya borrada. */
        this._wired = result;
        const { data, error } = result;
        if (data) {
            this.briefing = data;
            this.loadError = undefined;
            /* Si la escena ya se ejecuto en un pase anterior de la demo, se arranca en el
               estado final: el boton no debe invitar a crear un duplicado. Si el reinicio
               ya limpio los registros, se vuelve al briefing. */
            if (data.existingQuoteId) {
                this.phase = 'created';
                this.result = {
                    alreadyExisted: true,
                    opportunityId: data.existingOpportunityId,
                    quoteId: data.existingQuoteId,
                    message: 'Esta escena ya se ejecuto: la oportunidad y la oferta existen.'
                };
            } else if (this.phase === 'created') {
                this.resetToBriefing();
            }
        } else if (error) {
            this.loadError = this.readError(error);
            this.briefing = undefined;
        }
    }

    disconnectedCallback() {
        this.clearTimers();
    }

    // ── Estado de fase ───────────────────────────────────────────────────────────

    get isBriefing() {
        return this.phase === 'briefing';
    }

    get isRunning() {
        return this.phase === 'running';
    }

    get showVerdict() {
        return this.phase === 'verdict' || this.phase === 'created';
    }

    get isCreated() {
        return this.phase === 'created';
    }

    get isLoading() {
        return !this.briefing && !this.loadError;
    }

    get machine() {
        return this.briefing ? this.briefing.machine : undefined;
    }

    get hasMachine() {
        return !!this.machine;
    }

    get components() {
        const m = this.machine;
        if (!m || !m.components) return [];
        return m.components.map((c) => ({
            ...c,
            rowClass: c.atRisk ? 'component-row is-at-risk' : 'component-row',
            badgeLabel: c.atRisk ? 'En riesgo' : 'Soportado',
            badgeClass: c.atRisk ? 'badge badge-bad' : 'badge badge-good'
        }));
    }

    get riskComponent() {
        return this.components.find((c) => c.atRisk);
    }

    // ── Las cuatro preguntas del briefing ────────────────────────────────────────

    get questions() {
        const m = this.machine;
        const b = this.briefing;
        if (!b) return [];

        const model = (m && m.model) || 'la maquina';
        const age = m && m.ageYears ? `${m.ageYears} anos` : 'mas de una decada';
        const risk = this.riskComponent;
        const riskName = risk ? risk.productName || risk.name : 'el PC industrial';
        const who = b.contactName || 'el cliente';
        const role = b.contactTitle ? `, ${b.contactTitle},` : '';

        return [
            {
                id: 'why-problem',
                icon: 'utility:warning',
                tone: 'warn',
                title: 'Por que esto es un problema',
                body: `${who}${role} no esta reportando una averia: esta avisando de que ${riskName} corre un sistema operativo fuera de soporte. Mientras la maquina siga produciendo, el caso parece de baja urgencia, y por eso este tipo de peticion se queda semanas en una bandeja de correo. El riesgo real es que la parada llegue sin avisar y sin repuesto disponible.`
            },
            {
                id: 'what-problem',
                icon: 'utility:knowledge_base',
                tone: 'neutral',
                title: 'Cual es exactamente el problema',
                body: `${model}, instalada hace ${age}, monta ${
                    (m && m.installedConfig) || 'una configuracion heredada'
                }. El fin de soporte del sistema operativo deja la maquina sin parches de seguridad y sin garantia de compatibilidad con el software de linea. En cuanto seguridad corporativa la audita, acaba desconectada de la red.`
            },
            {
                id: 'how-solve',
                icon: 'utility:settings',
                tone: 'good',
                title: 'Como se resuelve',
                body: `Con el retrofit ${RECOMMENDATION.name}: se migra el PC a Windows 11 sobre la electronica ya instalada, sin sustituir la maquina. La CPU y la CU actuales son compatibles con la base del retrofit, asi que el trabajo es de campo y no pasa por ingenieria de proyecto.`
            },
            {
                id: 'why-solve',
                icon: 'utility:trending',
                tone: 'accent',
                title: 'Por que se debe resolver',
                body: `Un retrofit es una venta de servicio de ciclo corto sobre una maquina que ya esta pagada. Los precedentes de otros clientes se han cerrado en poco mas de un mes y por encima de los 6.800 EUR. El unico caso que se perdio fue el de una maquina demasiado antigua para el retrofit, que acabo en compra de maquina nueva: esperar no deja el problema donde estaba, lo encarece.`
            }
        ];
    }

    // ── Precedentes ──────────────────────────────────────────────────────────────

    get relatedRows() {
        return this.relatedCases.map((c) => {
            const outcome = {
                won: { label: 'Resuelto', cls: 'badge badge-good' },
                lost: { label: 'Perdido', cls: 'badge badge-bad' },
                open: { label: 'En curso', cls: 'badge badge-warn' }
            }[c.outcome];
            return {
                ...c,
                outcomeLabel: outcome.label,
                outcomeClass: outcome.cls,
                amountLabel: c.amount
                    ? `${c.amount.toLocaleString('es-ES')} EUR`
                    : '-',
                daysLabel: c.daysToClose ? `${c.daysToClose} d` : '-'
            };
        });
    }

    get relatedSummary() {
        const won = this.relatedCases.filter((c) => c.outcome === 'won');
        const avg = Math.round(
            won.reduce((sum, c) => sum + c.daysToClose, 0) / (won.length || 1)
        );
        return `${this.relatedCases.length} casos de otros clientes sobre maquinas de la misma linea. ${won.length} cerrados con retrofit, media de ${avg} dias.`;
    }

    // ── Ejecucion simulada del agente ────────────────────────────────────────────

    get stages() {
        return AGENT_STAGES.map((s, i) => {
            let state = 'pending';
            if (i < this.stageIndex) state = 'done';
            else if (i === this.stageIndex) state = 'active';
            return {
                ...s,
                stageClass: `stage stage-${state}`,
                iconName: state === 'done' ? 'utility:check' : 'utility:routing_offline',
                iconVariant: state === 'done' ? 'success' : 'inverse',
                isActive: state === 'active'
            };
        });
    }

    handleRunAdvisor() {
        this.clearTimers();
        this.phase = 'running';
        this.stageIndex = 0;
        this.createError = undefined;

        AGENT_STAGES.forEach((_, i) => {
            this._timers.push(
                setTimeout(() => {
                    this.stageIndex = i + 1;
                    if (i === AGENT_STAGES.length - 1) {
                        this.phase = 'verdict';
                    }
                }, STAGE_MS * (i + 1))
            );
        });
    }

    // ── Creacion real ────────────────────────────────────────────────────────────

    handleCreate() {
        this.creating = true;
        this.createError = undefined;

        createRetrofitOpportunityAndQuote({ caseId: this.recordId })
            .then((result) => {
                this.result = result;
                this.phase = 'created';
                this.toast(
                    result.alreadyExisted ? 'Oferta reutilizada' : 'Oferta creada',
                    result.message,
                    'success'
                );
                if (!result.alreadyExisted && result.quoteId) {
                    this._timers.push(
                        setTimeout(() => this.recheckMargins(result.quoteId), MARGIN_RECHECK_MS)
                    );
                }
            })
            .catch((error) => {
                this.createError = this.readError(error);
                this.toast('No se pudo crear la oferta', this.createError, 'error');
            })
            .finally(() => {
                this.creating = false;
            });
    }

    recheckMargins(quoteId) {
        refreshQuoteMargins({ quoteId })
            .then((result) => {
                /* Solo se sustituye si el segundo sellado ya tiene cifras: si el pricing
                   seguia corriendo, el primer resultado es mejor que uno a cero. */
                if (result && result.totalPrice) {
                    this.result = { ...result, alreadyExisted: this.result.alreadyExisted };
                }
            })
            .catch(() => {
                /* Un recalculo fallido no invalida la oferta ya creada. */
            });
    }

    // ── Reinicio de la demo ──────────────────────────────────────────────────────

    handleResetRequest() {
        this.confirmingReset = true;
    }

    handleResetCancel() {
        this.confirmingReset = false;
    }

    handleResetConfirm() {
        this.resetting = true;
        resetDemoState({ caseId: this.recordId })
            .then((result) => {
                this.toast('Demo reiniciada', result.message, 'success');
                this.resetToBriefing();
                /* getCaseBriefing es cacheable: hay que refrescarlo para que deje de ver
                   la oferta ya borrada y no reponga el estado final. */
                return refreshApex(this._wired);
            })
            .catch((error) => {
                this.toast('No se pudo reiniciar', this.readError(error), 'error');
            })
            .finally(() => {
                this.resetting = false;
                this.confirmingReset = false;
            });
    }

    resetToBriefing() {
        this.clearTimers();
        this.phase = 'briefing';
        this.stageIndex = -1;
        this.result = undefined;
        this.createError = undefined;
        this.confirmingReset = false;
    }

    get resetLabel() {
        return this.resetting ? 'Reiniciando...' : 'Reiniciar la demo';
    }

    get resultFigures() {
        const r = this.result;
        if (!r) return [];
        const currency = r.currencyCode || 'EUR';
        const rows = [];
        if (r.totalPrice != null) {
            rows.push({ id: 'total', label: 'Total de la oferta', value: `${this.money(r.totalPrice)} ${currency}` });
        }
        if (r.totalCost != null) {
            rows.push({ id: 'cost', label: 'Coste sellado', value: `${this.money(r.totalCost)} ${currency}` });
        }
        if (r.marginPct != null) {
            rows.push({ id: 'margin', label: 'Margen mezclado', value: `${this.money(r.marginPct)}%` });
        }
        if (r.lineCount != null) {
            rows.push({ id: 'lines', label: 'Lineas', value: String(r.lineCount) });
        }
        return rows;
    }

    get createLabel() {
        return this.creating ? 'Creando...' : 'Crear Oportunidad + Oferta';
    }

    // ── Navegacion ───────────────────────────────────────────────────────────────

    handleOpenQuote() {
        this.navigate(this.result && this.result.quoteId);
    }

    handleOpenOpportunity() {
        this.navigate(this.result && this.result.opportunityId);
    }

    handleOpenMachine() {
        this.navigate(this.machine && this.machine.id);
    }

    navigate(recordId) {
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    // ── Utilidades ───────────────────────────────────────────────────────────────

    money(value) {
        return Number(value).toLocaleString('es-ES', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    readError(error) {
        if (!error) return 'Error desconocido.';
        if (error.body && error.body.message) return error.body.message;
        if (Array.isArray(error.body) && error.body.length) return error.body[0].message;
        return error.message || String(error);
    }

    clearTimers() {
        this._timers.forEach((t) => clearTimeout(t));
        this._timers = [];
    }
}
