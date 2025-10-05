#!/usr/bin/env python3

import pandas as pd
import argparse
import re
import os


def convert_to_excel(input_file):
    lines = []
    with open(input_file, 'r', encoding="utf8") as f:
        lines = f.readlines()

    
    split_lines = [[x.strip() for x in re.split('\]|\[|\n', line) if x.strip() != ""] for line in lines]
    df = pd.DataFrame(split_lines, columns=['date', 'level', 'message'])
    df = df.join(df.loc[df['message'].str.startswith('Pod'),'message'].str.split(' | ', expand=True)[[1,4,7]])
    df.columns = ['date', 'level', 'message', 'pod', 'memory', 'cpu']
    df['memory'] = pd.to_numeric(df['memory'].str.replace('Mi', ''))
    df['cpu'] = pd.to_numeric(df['cpu'].str.replace('m', ''))
    df['date'] = pd.to_datetime(df['date'])
    return df

def main():
    df = convert_to_excel(r"E:\Projects\DataPipe\logs\data-ingestion\resource-logs\resource-monitor.log")

    # Configure pandas display options
    pd.set_option('display.max_columns', None)
    pd.set_option('display.width', None)
    pd.set_option('display.max_colwidth', 100)
    
    df.to_excel(r"E:\Projects\DataPipe\logs\data-ingestion\resource-logs\resource-monitor.xlsx", index=True)
    print(df)
        

if __name__ == "__main__":
    exit(main())