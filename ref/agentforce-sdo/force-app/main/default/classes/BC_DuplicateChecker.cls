/**
 * @description Salesforce 표준 Duplicate Rule 매칭 정보를 수집하는 책임만 갖는다.
 *              Lead INSERT 자체는 BC_RecordWriter가 AllowSave=true로 진행 (이 클래스는 정보만 모음).
 *
 * @group AutoLeadByBC
 *
 * @example
 * List&lt;Id&gt; matched = new BC_DuplicateChecker().findMatchedIds(lead);
 * if (!matched.isEmpty()) {
 *     lead.Duplicate_Suspect__c = true;
 *     lead.Duplicate_Suspect_Info__c = String.join(matched, ', ');
 * }
 *
 * @see BC_RecordWriter
 */
public with sharing virtual class BC_DuplicateChecker {

    /**
     * @description Lead 1건에 대해 표준 Duplicate Rule 매칭 record Id 전부 반환 (Set으로 중복 제거).
     *              null 입력 시 빈 리스트 반환.
     *
     * @param lead 매칭을 검사할 Lead 인스턴스 (DML 전 상태도 가능)
     * @return 매칭된 Lead/Contact 등의 Id 목록 (없으면 빈 리스트)
     */
    public virtual List<Id> findMatchedIds(Lead lead) {
        Set<Id> ids = new Set<Id>();
        if (lead == null) return new List<Id>();

        List<Datacloud.FindDuplicatesResult> results =
            Datacloud.FindDuplicates.findDuplicates(new List<Lead>{ lead });

        if (results == null) return new List<Id>();
        for (Datacloud.FindDuplicatesResult fdr : results) {
            if (fdr == null || fdr.getDuplicateResults() == null) continue;
            for (Datacloud.DuplicateResult dr : fdr.getDuplicateResults()) {
                if (dr == null || dr.getMatchResults() == null) continue;
                for (Datacloud.MatchResult mr : dr.getMatchResults()) {
                    if (mr == null || mr.getMatchRecords() == null) continue;
                    for (Datacloud.MatchRecord rec : mr.getMatchRecords()) {
                        if (rec != null && rec.getRecord() != null) {
                            Id matchedId = (Id) rec.getRecord().get('Id');
                            if (matchedId != null) ids.add(matchedId);
                        }
                    }
                }
            }
        }
        return new List<Id>(ids);
    }
}
