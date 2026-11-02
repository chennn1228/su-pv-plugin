# Substation PV Design for SketchUp

A SketchUp 2022 extension for photovoltaic module placement, array layout, roof constraints, electrical sizing, shading analysis, and generation estimates.

## Load

Load the main entry point in the SketchUp 2022 Ruby Console:

```ruby
load 'D:/Administrator Files/SEU/12.Project/260911_SU PV plugin/project/scripts/pv_toolbar.rb'
```

If the project is stored elsewhere, replace this path. Internal paths are resolved relative to the scripts. Reloading the entry point does not duplicate toolbar buttons.

The toolbar provides eight tools:

- Standard substation model
- PV module and generation
- PV array and generation
- Boundary constraints
- Electrical configuration
- Generation forecast
- CSV export
- SVG / DXF export

The forecast, CSV export, and layout export tools start with an empty selection and accept individual modules, arrays, or groups containing PV modules. Click to add objects, Ctrl-click to select nested modules, and press Enter to confirm. The forecast tool opens its workspace; the export tools open a save dialog. Export controls inside the forecast workspace use the same selection workflow.

CSV export sums the selected modules' baseline generation. Layout export produces matching SVG and DXF files in one save operation. DXF preserves horizontal projection dimensions in millimetres, layers, and editable text. Electrical circuit diagrams use the same paired SVG/DXF export workflow.

## Generation Data

The repository contains the 1° data indexes, but not the full hourly and monthly summary CSV files. The complete data is currently stored locally. After cloning or downloading this repository, copy the CSV files for all five models from an existing dataset into this structure:

```text
data/pv_generation/stride_1-1/
  index.json
  <model_directory>/
    hourly.csv
    monthly_hourly.csv
    row_index.json
```

The indexes are included with the code. CSV values and formats remain unchanged. Generation queries and tests that use the actual generation data require these files. The extension reads local files and does not require a network connection at runtime.

## Project Structure

| Path | Purpose |
| --- | --- |
| `data/model.skp` | Standard substation model; `.skb` backups are local files |
| `scripts/pv_toolbar.rb` | Main toolbar entry point |
| `scripts/tools/` | Implementations of the eight tools |
| `scripts/support/` | Layout, selection, scene extraction, and export helpers |
| `scripts/inspect_model.rb` | Inspection of top-level model components |
| `scripts/insert_model_faces.rb` | Face-data extraction and reconstruction |
| `scripts/merge_pv_generation.py` | Simulation time-series conversion and merging |
| `data/` | Module parameters, face data, and generation data |
| `data/pv_generation/stride_1-1/` | 1° dataset directory; indexes are tracked, full CSV files are supplied separately |
| `output/checks/` | Regenerable test fixtures and verification outputs |
| `ui/` | Module, array, forecast, electrical, and shared UI components |
| `icons/` | Local toolbar icons |
| `tests/` | Current functional checks; see the [test guide](tests/README.md) |
| `references/gb50797_2024/` | Local spacing references, figures, and source material |

Simulation source files may be stored outside the project. After conversion, the extension only reads the merged dataset; the original source drive does not need to remain available.

### Data Conversion

Pass the source directory to `scripts/merge_pv_generation.py` with `--source`. Each `<power>_excel_files` directory must map uniquely to a model in the module parameter table.

For each model, the converter generates `hourly.csv`, `monthly_hourly.csv`, and `row_index.json`. Model metadata and validation results are stored in the dataset's root `index.json`. Hourly values are checked against monthly and annual summaries, written, and read back for verification while preserving double precision.

Use `--model` to process one model. `--workers 4 --shards 4` processes azimuth ranges in parallel and merges the validated parts into one table per model. The index is updated after each model completes; `--finalize` revalidates all indexed models.

### Standard Model Updates

Save changes to `data/model.skp`, load `scripts/insert_model_faces.rb`, and run `SuPvFaces.capture` to refresh the face data. Then use the standard substation tool to insert it into a target model.

The `insert` operation reconstructs the extracted data. It does not update the source model or refresh previously inserted instances.

## Coordinates and Calculation Conventions

- World axes: +X east, +Y north, +Z up. Azimuth increases clockwise from north; tilt is measured from the world horizontal plane.
- Modules use the `PV_panel` tag. Each array is a separate group containing module component instances. Placement supports undo.
- Array clearances are displayed in centimetres. Sliders use 5 cm increments; manual entries use 1 cm increments. Limits depend on module projections and installation-plane dimensions.
- The active index supports five module models rated at 140, 480, 505, 560, and 630 W. Other records in the original parameter table are excluded from the tools and converter. Generation data must match the model exactly.
- The lookup grid covers azimuths 0°–359° and tilts 0°–90°, both at 1° intervals. An azimuth of 360° is equivalent to 0°. Fractional geometry angles are preserved; missing exact lookup values are not interpolated or replaced with neighbouring angles.
- The array workspace compares baseline generation with geometric shading corrections. External shading is yellow, self-shading is dark blue, and their union is green. Scene extraction uses visible faces and accounts for nested transformations and holes. Mixed selections are weighted using each module's generation data.
- Solar positions use Yangzhou, China: 32.4° N, 119.4° E, UTC+8, year 2025. Hourly positions are calculated automatically.
- Modules on `wall` and `fence` tags lie flush with the installation plane. Fence modules taller than the face may extend above its top edge.
- Layout drawings are projected along world Z. CSV export provides annual hourly generation; the drawing tool exports matching SVG and DXF plans.

See [Core Methods](docs/methods.md) and the [Technical Design Report](docs/technical_design.md) for equations and calculation details. Both documents are in Chinese.
