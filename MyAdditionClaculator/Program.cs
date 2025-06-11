// See https://aka.ms/new-console-template for more information
Console.WriteLine("Enter the first numer:");

int first = Convert.ToInt32(Console.ReadLine());
Console.WriteLine("Enter the second number:");
int second = Convert.ToInt32(Console.ReadLine());
 Console.WriteLine("The sum of the two numbers is: " + (first + second));


            int num1;
            int num2;
            string operation;
            
            Console.WriteLine($"Enter the first number:");
            int.TryParse(Console.ReadLine(), out num1);
            
            Console.WriteLine($"Enter the second number:");
            int.TryParse(Console.ReadLine(), out num2);
            
            Console.WriteLine($"Choose an operation: +,-,*,/");
            operation = Console.ReadLine();
            
            switch(operation)
            {
                case "+":
                    Console.WriteLine($"Result : {num1 + num2}");
                    break;
                case "-":
                    Console.WriteLine($"Result : {num1 - num2}");
                    break;
                case "*":
                    Console.WriteLine($"Result : {num1 / num2}");
                    break;
                case "/":
                    if(num2 == 0) 
                    {
                        Console.WriteLine("Error: Division by zero is not allowed");
                    }
                    else
                    {
                        Console.WriteLine($"Result : {num1 / num2}");
                    }
                    break;
                default:
                    Console.WriteLine("Invalid operation. \n Please choose +,-,* or /.");
                    break;
            }
            