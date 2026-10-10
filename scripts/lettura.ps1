# La regola per dire «la lettura delle conversazioni e' finita», uguale a scripts/lettura_finita.py (che usa il Mac).
# Esito-Lettura: 0 finita, 1 ancora in corso, 2 errore, 3 «Grafo»/«Pronto» visto ma non ancora «Fatto» (le versioni vecchie non
# lo scrivono: chi aspetta ripete qualche giro e poi accetta).
function Esito-Lettura($progresso) {
    $testi = @($progresso.events | ForEach-Object { [string]$_.text })
    if ($progresso.error) { return 2 }
    if ($progresso.done -or @($testi | Where-Object { $_ -match '^Fatto' }).Count -gt 0) { return 0 }
    if (@($testi | Where-Object { $_ -match '^(Grafo|Pronto)' }).Count -gt 0) { return 3 }
    return 1
}
