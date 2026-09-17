import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getOpenCaseAlert from '@salesforce/apex/COMEXI_AssetOverviewController.getOpenCaseAlert';

export default class ComexiAssetCaseAlert extends NavigationMixin(LightningElement) {
    @api recordId;

    alertCase;

    @wire(getOpenCaseAlert, { assetId: '$recordId' })
    wiredCase({ data }) {
        /* Un error aqui no se pinta: la banda es un atajo de la escena 01, no la fuente
           de verdad del caso. Si falla, la maquina sigue teniendo su related list de
           casos y la demo no se rompe con un cartel de error en la cabecera. */
        this.alertCase = data || undefined;
    }

    /** Sin caso abierto no se renderiza nada: ninguna banda roja vacia en el parque. */
    get hasCase() {
        return !!this.alertCase;
    }

    get reference() {
        const c = this.alertCase;
        return (c && (c.reference || c.caseNumber)) || '';
    }

    get eyebrow() {
        const c = this.alertCase;
        if (!c) return '';
        const retrofit = c.isRetrofit ? ' · Retrofit' : '';
        const priority = c.priority ? ` · Prioridad ${c.priority}` : '';
        return `Caso de servicio abierto${retrofit}${priority}`;
    }

    get title() {
        const c = this.alertCase;
        if (!c) return '';
        /* El asunto del guion ya lleva el numero delante ("174535 - PC + Win (Asset
           MSC000600)"), asi que repetirlo en el titulo seria redundante. */
        return c.subject || `Caso ${this.reference}`;
    }

    get hasDescription() {
        return !!(this.alertCase && this.alertCase.description);
    }

    get buttonLabel() {
        return `Abrir el caso ${this.reference}`;
    }

    get reportedBy() {
        const c = this.alertCase;
        if (!c || !c.contactName) return undefined;
        return c.contactName;
    }

    handleOpenCase() {
        if (!this.alertCase) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.alertCase.id, actionName: 'view' }
        });
    }
}
