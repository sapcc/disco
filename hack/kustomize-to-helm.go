package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/goccy/go-yaml"
)

func main() {
	var outPath string
	flag.StringVar(&outPath, "out", "",
		"The path to the helm-chart directory")
	flag.Parse()

	if outPath == "" {
		fmt.Println("--out must be specified")
		os.Exit(1)
	}

	dec := yaml.NewDecoder(bufio.NewReader(os.Stdin))
	for {
		data := map[string]any{}
		if err := dec.Decode(&data); err != nil {
			if err.Error() == "EOF" {
				break
			}
			handleError(err)
		}

		metadata, ok := data["metadata"]
		if !ok {
			continue
		}
		metadataMap, ok := metadata.(map[any]any)
		if !ok {
			continue
		}
		name, ok := metadataMap["name"]
		if !ok {
			continue
		}

		p, err := yaml.Marshal(data)
		handleError(err)

		dir := "templates"
		// Write CRDs to the /crds folder
		if data["kind"] == "CustomResourceDefinition" {
			dir = "crds"
		}

		err = os.MkdirAll(filepath.Join(outPath, dir), 0644)
		handleError(err)

		fileName := filepath.Join(outPath, dir, fmt.Sprintf("%s.yaml", name))
		fmt.Printf("writing file %s\n", fileName)
		err = os.WriteFile(fileName, p, 0644)
		handleError(err)
	}
}

func handleError(err error) {
	if err != nil {
		fmt.Println("fatal error", err.Error())
		os.Exit(1)
	}
}
