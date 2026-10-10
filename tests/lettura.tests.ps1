# Prova della regola lettura finita su Windows (gira su PowerShell, anche nel workflow Prove).
. "$PSScriptRoot\..\scripts\lettura.ps1"
$ko = 0
function Atteso($nome, $vero) { if ($vero) { Write-Host "  OK   $nome" } else { Write-Host "  MALE $nome"; $script:ko++ } }
function P($json) { $json | ConvertFrom-Json }
Atteso 'senza eventi: in corso'                   ((Esito-Lettura (P '{"done":false,"events":[]}')) -eq 1)
Atteso 'solo Cerco: in corso'                  ((Esito-Lettura (P '{"events":[{"text":"Cerco le conversazioni"}]}')) -eq 1)
Atteso 'Grafo da solo: quasi (3)'              ((Esito-Lettura (P '{"events":[{"text":"Grafo pronto: persone"}]}')) -eq 3)
Atteso 'Pronto da solo: quasi (3)'             ((Esito-Lettura (P '{"events":[{"text":"Pronto: 1 conversazioni"}]}')) -eq 3)
Atteso 'Fatto: finita'                         ((Esito-Lettura (P '{"events":[{"text":"Grafo: 8 entita"},{"text":"Fatto: 9 conversazioni"}]}')) -eq 0)
Atteso 'done vero: finita'                        ((Esito-Lettura (P '{"done":true,"events":[]}')) -eq 0)
Atteso 'errore: errore anche con Fatto'         ((Esito-Lettura (P '{"error":"si e rotto","events":[{"text":"Fatto: 1"}]}')) -eq 2)
Atteso 'errore nullo non e'' un errore'           ((Esito-Lettura (P '{"error":null,"events":[]}')) -eq 1)
if ($ko -gt 0) { Write-Host "$ko prove rosse"; exit 1 }
Write-Host "tutte verdi"
