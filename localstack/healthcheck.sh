#!/bin/bash

curl -f http://localhost:4566/_localstack/health || exit 1
