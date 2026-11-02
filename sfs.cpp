
#include <iostream>
#include <fstream>
#include <string>
#include <limits>
#include <cstdlib>
using namespace std;

// Oracle database details
string DB_USER = "railway";
string DB_PASS = "railway123";
string DB_HOST = "localhost:1521/XEPDB1";

// Run PL/SQL code using SQL*Plus
void runSQL(string query)
{
    ofstream file("railway.sql");

    file << "SET SERVEROUTPUT ON\n";
    file << "SET FEEDBACK ON\n";
    file << query << "\n";
    file << "EXIT;\n";
    file.close();

    string command = "sqlplus -S " + DB_USER + "/" +
                     DB_PASS + "@" + DB_HOST + " @railway.sql";

    system(command.c_str());
    remove("railway.sql");
}

// 1. Book ticket
void bookTicket()
{
    string name, phone, date;
    int age, train;
    char gender;

    cin.ignore(numeric_limits<streamsize>::max(), '\n');

    cout << "Enter passenger name: ";
    getline(cin, name);

    cout << "Enter age: ";
    cin >> age;

    cout << "Enter gender (M/F/O): ";
    cin >> gender;

    cout << "Enter phone number: ";
    cin >> phone;

    cout << "Enter train number: ";
    cin >> train;

    cout << "Enter travel date (DD-MM-YYYY): ";
    cin >> date;

    if (age < 1 || age > 120 || phone.length() != 10)
    {
        cout << "Invalid age or phone number!\n";
        return;
    }

    string query =
        "BEGIN sp_book_ticket('" + name + "'," +
        to_string(age) + ",'" + gender + "','" +
        phone + "'," + to_string(train) +
        ",TO_DATE('" + date + "','DD-MM-YYYY')); END;";

    runSQL(query);
}

// 2. Check PNR status
void checkPNR()
{
    int pnr;

    cout << "Enter PNR number: ";
    cin >> pnr;

    runSQL("BEGIN sp_pnr_status(" +
           to_string(pnr) + "); END;");
}

// 3. Cancel ticket
void cancelTicket()
{
    int pnr;

    cout << "Enter PNR to cancel: ";
    cin >> pnr;

    runSQL("BEGIN sp_cancel_ticket(" +
           to_string(pnr) + "); END;");
}

// 4. Passenger list
void passengerList()
{
    int train;
    string date;

    cout << "Enter train number: ";
    cin >> train;

    cout << "Enter travel date (DD-MM-YYYY): ";
    cin >> date;

    runSQL(
        "BEGIN sp_passenger_list(" +
        to_string(train) +
        ",TO_DATE('" + date +
        "','DD-MM-YYYY')); END;"
    );
}

// 5. Generate simple HTML report
void generateReport()
{
    ofstream file("report.html");

    file << "<html><head><title>Railway Report</title>"
         << "<style>"
         << "body{font-family:Arial;background:#eef2f7;padding:30px;}"
         << "h1{color:#17365d;}"
         << ".box{background:white;padding:20px;border-radius:10px;}"
         << "</style></head><body>";

    file << "<div class='box'>";
    file << "<h1>Railway Management System</h1>";
    file << "<h2>Project Report</h2>";
    file << "<p>Railway ticket management project using C++ "
         << "and Oracle PL/SQL.</p>";
    file << "<p>Features: Booking, PNR Status, Cancellation "
         << "and Passenger List.</p>";
    file << "</div></body></html>";

    file.close();

    cout << "HTML report created successfully!\n";

    system("start report.html");
}

// Main function
int main()
{
    int choice;

    do
    {
        cout << "\n===== RAILWAY MANAGEMENT SYSTEM =====\n";
        cout << "1. Book Ticket\n";
        cout << "2. PNR Status\n";
        cout << "3. Cancel Ticket\n";
        cout << "4. Passenger List\n";
        cout << "5. Generate HTML Report\n";
        cout << "6. Exit\n";
        cout << "Enter your choice: ";

        if (!(cin >> choice))
        {
            cin.clear();
            cin.ignore(numeric_limits<streamsize>::max(), '\n');
            cout << "Please enter a valid number!\n";
            continue;
        }

        switch (choice)
        {
            case 1:
                bookTicket();
                break;

            case 2:
                checkPNR();
                break;

            case 3:
                cancelTicket();
                break;

            case 4:
                passengerList();
                break;

            case 5:
                generateReport();
                break;

            case 6:
                cout << "Thank you for using Railway System!\n";
                break;

            default:
                cout << "Invalid choice!\n";
        }

    } while (choice != 6);

    return 0;
}
