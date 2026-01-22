#!/usr/bin/env bats

load "../lib/utils.sh"

@test "log_success imprime en verde" {
  run log_success "Hola"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hola"* ]]
}