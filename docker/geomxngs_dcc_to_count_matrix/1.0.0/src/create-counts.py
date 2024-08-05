import argparse
import configparser
import glob
import json
import os
from zipfile import ZipFile

import anndata
import numpy as np
import pandas as pd

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dcc", help="DCC folder", required=True)
    parser.add_argument("--ini", help="INI file", required=True)
    parser.add_argument(
        "--output",
        help="Output directory to output counts.h5ad, counts.txt, and metadata.txt",
        required=True,
    )
    parser.add_argument(
        "--pkc",
        dest="pkc",
        help="PKC file or PKC zip file containing target information",
        required=True,
    )
    parser.add_argument(
        "--lab-worksheet", dest="lab_worksheet", help="Lab worksheet", required=True
    )
    parser.add_argument("--dataset", dest="dataset", help="Dataset Excel file", required=True)

    args = parser.parse_args()
    dcc_dir_path = args.dcc

    output = args.output

    pkc_path = args.pkc
    lab_worksheet_path = args.lab_worksheet
    ini_path = args.ini
    dataset_path = args.dataset

    config = configparser.ConfigParser()
    config.optionxform = str  # prevent conversion of keys to lowercase
    config.read(ini_path)

    targets = list(config["Targets"].keys())
    if len(targets) == 0:
        raise ValueError("No targets found")

    dcc_paths = glob.glob(os.path.join(dcc_dir_path, "*.dcc"))
    if len(dcc_paths) == 0:
        raise ValueError('No DCC files found')
    target2index = {}
    for i in range(len(targets)):
        target2index[targets[i]] = i
    X = np.zeros(shape=(len(dcc_paths), len(targets)), dtype="int")
    for i in range(len(dcc_paths)):
        dcc_path = dcc_paths[i]
        with open(dcc_path, "rt") as dcc_in:
            for line in dcc_in:
                line = line.strip()
                if line == "<Code_Summary>":
                    break
            for line in dcc_in:
                line = line.strip()
                if line == "</Code_Summary>":
                    break
                tokens = line.split(",")
                assert len(tokens) == 2
                target = tokens[0]
                target_index = target2index[target]
                count = int(tokens[1])
                X[i, target_index] = count

                # e.g. RTS0052259,3

    # add info from pkc file(s)
    pkcs = []
    if pkc_path.lower().endswith(".zip"):
        with ZipFile(pkc_path, "r") as z:
            for zip_file_entry in z.filelist:
                # ignore __MACOSX/._file_name.pkc files
                if zip_file_entry.filename.lower().endswith(
                        ".pkc"
                ) and not zip_file_entry.filename.lower().startswith("__"):
                    pkcs.append(json.loads(z.read(zip_file_entry)))
    else:
        with open(pkc_path, "rb") as f:
            pkcs.append(json.load(f))
    pkc_df = None
    for pkc in pkcs:
        rts_ids = []
        genes = []
        probes = []
        genome = pkc["Name"]
        for target in pkc["Targets"]:
            display_name = target["DisplayName"]
            for probe in target["Probes"]:
                probes.append(probe["DisplayName"])
                rts_ids.append(probe["RTS_ID"])
                genes.append(display_name)

        df = pd.DataFrame(index=rts_ids, data={"gene": genes, "probe": probes})
        df["genome"] = genome
        pkc_df = df if pkc_df is None else pd.concat((pkc_df, df))
    var = pd.DataFrame(index=targets)
    obs = pd.DataFrame(index=[os.path.splitext(os.path.basename(path))[0] for path in dcc_paths])
    obs["plate_well"] = obs.index.str.split("-").str[-2:].str.join("-")  # e.g. B-A02
    var = var.join(pkc_df)

    with open(lab_worksheet_path, "rt") as lab_worksheet_in:
        for line in lab_worksheet_in:
            line = line.strip()
            if line == "Annotations":
                break
        lab_worksheet_df = pd.read_csv(lab_worksheet_in, sep="\t")

    roi_column = lab_worksheet_df.columns[lab_worksheet_df.columns.str.lower().get_loc('roi')]
    slide_name_column = lab_worksheet_df.columns[lab_worksheet_df.columns.str.lower().get_loc('slide name')]
    segment_column = lab_worksheet_df.columns[lab_worksheet_df.columns.str.lower().get_loc('segment')]
    lab_worksheet_df[roi_column] = lab_worksheet_df[roi_column].str.replace("=", "").str.replace('"', "")
    lab_worksheet_df["id"] = (
            lab_worksheet_df[slide_name_column]
            + " | "
            + lab_worksheet_df[roi_column]
            + " | "
            + lab_worksheet_df[segment_column]
    )
    lab_worksheet_df = lab_worksheet_df.set_index("id")
    # keep slide name for controls

    lab_worksheet_df = lab_worksheet_df.rename({slide_name_column: "SlideName"}, axis=1)

    dataset_df = pd.read_excel(dataset_path, index_col="SegmentDisplayName")
    lab_worksheet_controls_df = lab_worksheet_df[~lab_worksheet_df.index.isin(dataset_df.index)]
    if len(lab_worksheet_controls_df) > 0:
        dataset_df = pd.concat((dataset_df, lab_worksheet_controls_df[["SlideName"]]))

    lab_worksheet_df = lab_worksheet_df[["Sample_ID"]]
    obs_meta_df = lab_worksheet_df.join(dataset_df)
    obs_meta_df = obs_meta_df.drop_duplicates("Sample_ID").set_index("Sample_ID")
    obs = obs.join(obs_meta_df)

    adata = anndata.AnnData(X=X, obs=obs, var=var, dtype=X.dtype)
    for c in adata.obs.columns:
        if pd.api.types.is_object_dtype(adata.obs[c].dtype):
            adata.obs[c] = adata.obs[c].astype(str)
    os.makedirs(output, exist_ok=True)
    adata.write(os.path.join(output, "counts.h5ad"))
    df = adata.T.to_df()
    df.insert(0, "Gene", adata.var["gene"])
    df.insert(1, "Probe", adata.var["probe"])
    df.to_csv(os.path.join(output, "counts.txt"), sep="\t")
    adata.obs.to_csv(os.path.join(output, "metadata.txt"), sep="\t")
