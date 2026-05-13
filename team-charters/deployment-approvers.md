# Deployment Approvers

Team GitHub: [@Jigen-lab/deployment-approvers](https://github.com/orgs/Jigen-lab/teams/deployment-approvers)

Questo team approva i deploy in produzione GCP attraverso GitHub Environments. È il livello operativo di gate fra "il codice è stato mergiato su `main`" e "Terraform applica davvero in produzione".

## Quando viene chiamato in causa

Quando un workflow `tf-apply-*-prod.yml` parte (ad esempio dopo il merge di una PR su `main`), GitHub Environments **mette in pausa** l'esecuzione finché un membro di questo team non approva o rifiuta.

## Responsabilità dell'approvatore

Davanti alla richiesta di approval:

1. Apri i log del workflow e leggi il `terraform plan` allegato
2. Verifica che le risorse modificate/create siano attese e ragionevoli rispetto allo scopo della PR
3. Verifica che il cliente impattato (se applicabile) sia consapevole / ci sia issue link al cambio
4. Approva, **oppure** rifiuta motivando

## Quando rifiutare

Rifiuta sempre se:

- Il plan **rimuove** risorse persistenti (drop di tabelle, cancellazione bucket, distruzione VM con dati, ecc.) senza un commento esplicito o una issue di tracking che spieghi il "perché"
- Il plan tocca configurazioni di **security** (IAM bindings, KMS, org policy, audit log sinks) senza giustificazione documentata
- L'**orario** è fuori dalla finestra di deploy concordata (es. weekend, late night) e non c'è ragione operativa per la fretta
- Manca un'**issue di tracking** che spiega il motivo del deploy

## Sincronizzazione con Cloud Identity

Questo team va tenuto sincronizzato manualmente con il Cloud Identity group `gcp-deployment-approvers@jigen.ch`, che riceve i ruoli IAM `roles/viewer` su tutto + `roles/logging.viewer` su `prj-c-logging` (così i membri possono leggere i `terraform plan` con cognizione di causa).

**Pattern**: quando si aggiunge/rimuove un membro qui, aggiornare anche il gruppo Cloud Identity. In futuro si automatizza via Terraform (`github_team_membership` + `google_cloud_identity_group_membership` declarative).

## Membership

L'elenco aggiornato dei membri vive sulla [pagina del team](https://github.com/orgs/Jigen-lab/teams/deployment-approvers). Mantenere il team piccolo e fidato (3-5 persone) per evitare deresponsabilizzazione: meno approvers → ognuno legge più attentamente.

## Riferimenti

- Issue di creazione: [Jigen-lab/infra-gcp#10](https://github.com/Jigen-lab/infra-gcp/issues/10)
- Branch protection del repo Terraform: [Jigen-lab/infra-gcp#9](https://github.com/Jigen-lab/infra-gcp/issues/9)
- Foundation doc §12.2 — GitHub Environments e approvazioni
