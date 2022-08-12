import React from 'react'
import { useTable, usePagination } from 'react-table';

import styles from "./DataTable.module.scss";

const DataTable = ({name, filterData = [], columns, data }: any) => {
    const {
        getTableProps,
        getTableBodyProps,
        headerGroups,
        prepareRow,
        page,
        canPreviousPage,
        canNextPage,
        pageOptions,
        pageCount,
        gotoPage,
        nextPage,
        previousPage,
        setPageSize,
        state: { pageIndex, pageSize },
      }:any = useTable(
        {
          columns,
          data,
        },
        usePagination
      )
    
      const filterList = filterData.map((filterBy: any) => {
        return (
          <li>{filterBy}</li>
        );
      });
     
      return (
        <>
          <div className={styles.tableFilterContainer}>
            <h3>  {1}-{pageCount} of { data.length } {name} </h3>
            <ul>
              {filterList}
            </ul>
          </div>
          <div>
          <table {...getTableProps()}>
            <thead>
              {headerGroups.map((headerGroup: { getHeaderGroupProps: () => JSX.IntrinsicAttributes & React.ClassAttributes<HTMLTableRowElement> & React.HTMLAttributes<HTMLTableRowElement>; headers: any[]; }) => (
                <tr {...headerGroup.getHeaderGroupProps()}>
                  {headerGroup.headers.map(column => (
                    <th {...column.getHeaderProps()}>{column.render('Header')}</th>
                  ))}
                </tr>
              ))}
            </thead>
            <tbody {...getTableBodyProps()}>
              {page.map((row: { getRowProps: () => JSX.IntrinsicAttributes & React.ClassAttributes<HTMLTableRowElement> & React.HTMLAttributes<HTMLTableRowElement>; cells: any[]; }, i: any) => {
                prepareRow(row)
                return (
                  <tr {...row.getRowProps()}>
                    {row.cells.map(cell => {
                      return <td {...cell.getCellProps()}>{cell.render('Cell')}</td>
                    })}
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
        <div className={styles.pagination}>
          <span>
              Page{' '}
              <strong>
                {pageIndex + 1} of {pageOptions.length}
              </strong>{' '}
          </span>
          <span>
            <button onClick={() => previousPage()} disabled={!canPreviousPage}>
              {'Prev'}
            </button>{' - '}
            <button onClick={() => nextPage()} disabled={!canNextPage}>
              {'Next'}
            </button>{' '}
          </span>
        </div>
      </>
    )
};

export default DataTable;