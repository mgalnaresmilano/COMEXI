// Mete al usuario que ejecuta en los grupos publicos que aprueban la oferta.
//
// La orquestacion RLM_Quote_Smart_Approval asigna sus pasos a los grupos publicos
// Manager, Director y VP. En esta org esos grupos solo contienen el grupo del rol CEO,
// y el usuario de demo no tiene rol asignado: sin esto el work item se crea pero nadie
// lo ve, y la pestana Approvals de la oferta aparece vacia.
//
// En la demo las tres firmas recaen en la misma persona para no consumir mas licencias.

List<String> groupNames = new List<String>{ 'Manager', 'Director', 'VP' };
Id userId = UserInfo.getUserId();

Map<Id, String> groupById = new Map<Id, String>();
for (Group g : [SELECT Id, DeveloperName FROM Group
                WHERE DeveloperName IN :groupNames AND Type = 'Regular']) {
    groupById.put(g.Id, g.DeveloperName);
}
for (String name : groupNames) {
    if (!groupById.values().contains(name)) {
        throw new IllegalArgumentException('Falta el grupo publico ' + name
            + '. Lo crea el preset de la org, no este repositorio.');
    }
}

Set<Id> alreadyMember = new Set<Id>();
for (GroupMember gm : [SELECT GroupId FROM GroupMember
                       WHERE GroupId IN :groupById.keySet() AND UserOrGroupId = :userId]) {
    alreadyMember.add(gm.GroupId);
}

List<GroupMember> toIns = new List<GroupMember>();
for (Id groupId : groupById.keySet()) {
    if (alreadyMember.contains(groupId)) continue;
    toIns.add(new GroupMember(GroupId = groupId, UserOrGroupId = userId));
}
if (!toIns.isEmpty()) insert toIns;

System.debug('Aprovador ' + UserInfo.getName()
    + ' | grups ja assignats: ' + alreadyMember.size()
    + ' | grups afegits: ' + toIns.size());
