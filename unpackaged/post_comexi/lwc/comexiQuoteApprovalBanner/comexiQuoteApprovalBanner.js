import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import {
    getRecord,
    getFieldValue,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import STATUS_FIELD from '@salesforce/schema/Quote.RLM_Approval_Status__c';
import LEVEL_FIELD from '@salesforce/schema/Quote.RLM_Approval_Level__c';
import DISCOUNT_FIELD from '@salesforce/schema/Quote.RLM_Discount_Percent__c';
import MAX_LINE_FIELD from '@salesforce/schema/Quote.COMEXI_Max_Line_Discount_Pct__c';
import MARGIN_FIELD from '@salesforce/schema/Quote.COMEXI_Blended_Margin_Pct__c';
import getApprovalState from '@salesforce/apex/COMEXI_QuoteApprovalController.getApprovalState';
import submitForApproval from '@salesforce/apex/COMEXI_QuoteApprovalController.submitForApproval';

/* Se escuchan para detectar dos cosas: que el motor de pricing ha movido el descuento y
   que la orquestacion ha escrito el estado. Los niveles y el estado los decide Apex
   leyendo el framework nativo, que es la unica fuente. */
const FIELDS = [STATUS_FIELD, LEVEL_FIELD, DISCOUNT_FIELD, MAX_LINE_FIELD, MARGIN_FIELD];

/* Mismo orden que los pasos de aprobacion de RLM_Quote_Smart_Approval. */
const LEVEL_NAMES = ['Manager', 'Director de Servicio', 'VP'];
const LEVEL_LABELS = LEVEL_NAMES.map((name, i) => `Nivel ${i + 1} - ${name}`);

export default class ComexiQuoteApprovalBanner extends LightningElement {
    @api recordId;

    state;
    loadError;
    working = false;

    _stateWire;
    _lastSignature;

    @wire(getApprovalState, { quoteId: '$recordId' })
    wiredState(result) {
        this._stateWire = result;
        const { data, error } = result;
        if (data) {
            this.state = data;
            this.loadError = undefined;
        } else if (error) {
            this.loadError = this.readError(error);
        }
    }

    /* getApprovalState es cacheable, asi que por si solo no reacciona ni a un reprecio de
       lineas ni a la escritura de estado que hace la orquestacion en un paso de fondo.
       Este wire escucha el registro via LDS y fuerza el refresco en cuanto alguno de esos
       tres numeros cambia. */
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data }) {
        if (!data) return;
        const signature = [
            getFieldValue(data, STATUS_FIELD),
            getFieldValue(data, LEVEL_FIELD),
            getFieldValue(data, DISCOUNT_FIELD)
        ].join('|');
        if (this._lastSignature !== undefined && this._lastSignature !== signature) {
            this.refreshState();
        }
        this._lastSignature = signature;
    }

    // ── Datos derivados para la plantilla ────────────────────────────────────────

    get ready() {
        return !!this.state;
    }

    get status() {
        return this.state ? this.state.status : null;
    }

    get requiredLevels() {
        return this.state ? this.state.requiredLevels : 0;
    }

    get discountLabel() {
        return this.pct(this.state && this.state.discountPct);
    }

    get maxLineDiscountLabel() {
        return this.pct(this.state && this.state.maxLineDiscountPct);
    }

    get marginLabel() {
        return this.pct(this.state && this.state.marginPct);
    }

    pct(value) {
        return value === null || value === undefined ? '—' : `${value.toFixed(2)}%`;
    }

    /** "Manager", "Manager y Director de Servicio", "Manager, Director de Servicio y VP". */
    get approverList() {
        const names = LEVEL_NAMES.slice(0, this.requiredLevels);
        if (names.length === 0) return '';
        if (names.length === 1) return names[0];
        return `${names.slice(0, -1).join(', ')} y ${names[names.length - 1]}`;
    }

    get headline() {
        if (!this.state) return '';
        switch (this.state.status) {
            case 'NotRequired':
                return 'Sin aprobación: ninguna línea llega al umbral';
            case 'NotSubmitted':
                return this.requiredLevels === 1
                    ? 'Necesita aprobación de un nivel'
                    : `Necesita aprobación de ${this.requiredLevels} niveles`;
            case 'Pending':
                return `En aprobación · ${this.state.stepLabel}`;
            case 'Approved':
                return 'Descuento aprobado';
            case 'Rejected':
                return 'Descuento rechazado';
            case 'Recalled':
                return 'Solicitud retirada';
            default:
                return '';
        }
    }

    get detail() {
        if (!this.state) return '';
        const blended = this.discountLabel;
        const line = this.maxLineDiscountLabel;
        switch (this.state.status) {
            case 'NotRequired':
                return `Descuento ${blended} y ninguna línea por encima del umbral. El vendedor cierra sin pedir permiso a nadie.`;
            case 'NotSubmitted':
                return `Descuento mezclado ${blended}, pero la línea más agresiva llega al ${line}: firman ${this.approverList}.`;
            case 'Pending':
                return `Nivel ${this.state.currentLevel} de ${this.requiredLevels}, pendiente de ${this.approverName}.`;
            case 'Approved':
                return `Descuento ${blended} aprobado con ${this.state.approvedLevels} de ${this.requiredLevels} niveles.`;
            case 'Rejected':
                return `Descuento ${blended} rechazado. Ajusta la oferta y vuelve a enviarla.`;
            case 'Recalled':
                return 'Solicitud retirada. Puedes volver a enviarla mientras alguna línea siga por encima del umbral.';
            default:
                return '';
        }
    }

    get approverName() {
        return (this.state && this.state.approverName) || 'el aprobador asignado';
    }

    get themeClass() {
        const base = 'slds-notify slds-notify_alert slds-theme_alert-texture comexi-banner';
        switch (this.status) {
            case 'NotRequired':
            case 'Approved':
                return `${base} slds-theme_success`;
            case 'Rejected':
                return `${base} slds-theme_error`;
            case 'Pending':
                return `${base} slds-theme_info`;
            default:
                return `${base} slds-theme_warning`;
        }
    }

    get iconName() {
        switch (this.status) {
            case 'NotRequired':
            case 'Approved':
                return 'utility:success';
            case 'Rejected':
                return 'utility:error';
            case 'Pending':
                return 'utility:clock';
            default:
                return 'utility:warning';
        }
    }

    /** Escalera de niveles: da la lectura visual de cuantas firmas faltan. */
    get levels() {
        const total = this.requiredLevels;
        if (!this.state || total === 0) return [];
        const approved = this.state.approvedLevels || 0;
        const items = [];
        for (let i = 1; i <= total; i++) {
            let icon = 'utility:record';
            let cssClass = 'comexi-level';
            if (i <= approved) {
                icon = 'utility:check';
                cssClass = 'comexi-level comexi-level_done';
            } else if (this.status === 'Pending' && i === this.state.currentLevel) {
                icon = 'utility:clock';
                cssClass = 'comexi-level comexi-level_current';
            }
            items.push({ key: i, label: LEVEL_LABELS[i - 1], icon, cssClass });
        }
        return items;
    }

    get showSubmit() {
        return this.state && this.state.canSubmit;
    }

    /* La decision se toma en la pestana Approvals, que es donde el circuito nativo deja la
       traza. El banner solo se encarga de que nadie la busque en otro sitio. */
    get showApprovalsHint() {
        return this.status === 'Pending';
    }

    get submitLabel() {
        return this.requiredLevels === 1
            ? 'Enviar a aprobación'
            : `Enviar a aprobación (${this.requiredLevels} niveles)`;
    }

    // ── Acciones ─────────────────────────────────────────────────────────────────

    /* El reprecio de las lineas y la escritura de estado de la orquestacion pasan en
       servidor. Si la cache de LDS no se enterase, este boton fuerza la relectura sin
       recargar la pagina. */
    handleRefresh() {
        this.working = true;
        notifyRecordUpdateAvailable([{ recordId: this.recordId }])
            .then(() => this.refreshState())
            .catch((error) => {
                this.toast('No se pudo refrescar', this.readError(error), 'error');
            })
            .finally(() => {
                this.working = false;
            });
    }

    handleSubmit() {
        this.working = true;
        submitForApproval({ quoteId: this.recordId })
            .then((state) => {
                this.state = state;
                this.toast(
                    'Enviada a aprobación',
                    'Aprueba o rechaza desde la pestaña Approvals de la oferta.',
                    'success'
                );
                /* La orquestacion escribe el estado del path, asi que se avisa a LDS para
                   que el resto de la pagina lo vea sin recargar. */
                return notifyRecordUpdateAvailable([{ recordId: this.recordId }]).then(() =>
                    this.refreshState()
                );
            })
            .catch((error) => {
                this.toast('No se pudo enviar', this.readError(error), 'error');
            })
            .finally(() => {
                this.working = false;
            });
    }

    refreshState() {
        return this._stateWire ? refreshApex(this._stateWire) : Promise.resolve();
    }

    readError(error) {
        if (!error) return 'Error desconocido.';
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return JSON.stringify(error);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
